import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/reference_category.dart';
import '../services/category_service.dart';
import '../services/image_asset_service.dart';
import '../services/image_save_service.dart';
import '../services/image_share_service.dart';
import '../services/messaging_service.dart';
import '../services/report_service.dart';
import '../widgets/home_button.dart';
import '../widgets/image_delivery.dart';
import '../widgets/report_dialog.dart';

Future<Uint8List> _downloadImageBytes(String url) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError(
      'Image download failed with status ${response.statusCode}.',
    );
  }
  if (response.bodyBytes.isEmpty) {
    throw StateError('The downloaded image is empty.');
  }
  return response.bodyBytes;
}

String initialsFor(String? name) {
  final trimmed = (name ?? '').trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  final first = parts.first.isNotEmpty ? parts.first[0] : '';
  final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
  return (first + second).toUpperCase();
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherLoginName,
  });

  final String conversationId;
  final String otherUserId;
  final String? otherLoginName;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  late final MessagingService _messagingService;
  late final ReportService _reportService;
  RealtimeChannel? _channel;

  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _busyImageMessageId;
  String? _errorMessage;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _messagingService = MessagingService(_supabase);
    _reportService = ReportService(_supabase);
    _loadMessages();
    _subscribeToNewMessages();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeToNewMessages() {
    _channel = _supabase
        .channel('conversation-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (payload) {
            if (mounted) unawaited(_loadMessages(showLoading: false));
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final messages = await _messagingService.listMessages(
        widget.conversationId,
      );
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      unawaited(_messagingService.markConversationRead(widget.conversationId));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load messages.\n$error';
      });
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _textController.clear();
    try {
      await _messagingService.sendMessage(
        recipientId: widget.otherUserId,
        body: text,
      );
      await _loadMessages(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _sendImage() async {
    if (_isSending) return;
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _isSending = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final prepared = await _messagingService.prepareImageUpload();
      await _messagingService.uploadMessageImageBytes(bytes, prepared);
      await _messagingService.sendMessage(
        recipientId: widget.otherUserId,
        imageStoragePath: prepared.storagePath,
      );
      await _loadMessages(showLoading: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// Reports the person, from the conversation's own menu.
  ///
  /// Separate from reporting a message because the complaint is often about a
  /// pattern rather than one thing said — and because somebody being harassed
  /// should not have to pick which message was the worst one before they can
  /// ask for help.
  Future<void> _reportPerson() async {
    final who = widget.otherLoginName ?? 'this person';
    final outcome = await showReportDialog(
      context: context,
      title: 'Report $who',
      subtitle: 'Tell us what is wrong and we will look at it.',
      blockLabel: 'Also block $who',
    );
    if (outcome == null || !mounted) return;

    await _send(
      () => _reportService.reportUser(
        userId: widget.otherUserId,
        conversationId: widget.conversationId,
        reason: outcome.reason,
        details: outcome.details,
      ),
      alsoBlock: outcome.alsoBlock,
    );
  }

  Future<void> _reportMessage(ChatMessage message) async {
    final who = widget.otherLoginName ?? 'this person';
    final outcome = await showReportDialog(
      context: context,
      title: 'Report this message',
      subtitle: 'Tell us what is wrong and we will look at it.',
      blockLabel: 'Also block $who',
    );
    if (outcome == null || !mounted) return;

    await _send(
      () => _reportService.reportMessage(
        messageId: message.id,
        reason: outcome.reason,
        details: outcome.details,
      ),
      alsoBlock: outcome.alsoBlock,
    );
  }

  /// Files the report, then blocks if that was asked for.
  ///
  /// In that order, and the block is not allowed to take the report down with
  /// it: someone who reports and blocks has said the more important thing
  /// first, and a failure to block should not read as a failure to report.
  Future<void> _send(
    Future<void> Function() file, {
    required bool alsoBlock,
  }) async {
    try {
      await file();

      if (alsoBlock) {
        try {
          await _messagingService.blockUser(widget.otherUserId);
        } catch (error) {
          debugPrint('Reported, but the block failed: $error');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alsoBlock
                ? 'Thank you. We will look into it, and they have been blocked.'
                : 'Thank you. We will look into it.',
          ),
        ),
      );

      if (alsoBlock && mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// The actions on a message that is not yours.
  ///
  /// Text messages had no menu at all before this: only images were long
  /// pressable, so the one thing in the app most likely to need reporting —
  /// something somebody wrote — was the one thing that could not be.
  Future<void> _showMessageActions(ChatMessage message) async {
    if (message.isMine || _busyImageMessageId != null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report this message'),
              onTap: () => Navigator.of(sheetContext).pop('report'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'report' && mounted) await _reportMessage(message);
  }

  Future<void> _showImageActions(ChatMessage message) async {
    final imageUrl = message.imageUrl;
    if (imageUrl == null || _busyImageMessageId != null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text('Save to a category'),
                  subtitle: const Text('Add this image to your library'),
                  onTap: () => Navigator.of(sheetContext).pop('library'),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share_outlined),
                  title: const Text('Share'),
                  onTap: () => Navigator.of(sheetContext).pop('share'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(ImageSaveService.actionLabel),
                  onTap: () => Navigator.of(sheetContext).pop('photos'),
                ),
                if (!message.isMine) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Report this image'),
                    onTap: () => Navigator.of(sheetContext).pop('report'),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !mounted) return;

    switch (action) {
      case 'library':
        await _saveImageToLibrary(message, imageUrl);
      case 'share':
        await _shareImage(message, imageUrl);
      case 'photos':
        await _saveImageToPhotos(message, imageUrl);
      case 'report':
        await _reportMessage(message);
    }
  }

  Future<void> _saveImageToLibrary(ChatMessage message, String imageUrl) async {
    setState(() => _busyImageMessageId = message.id);
    try {
      final categories = await CategoryService(_supabase).listCategories();
      if (!mounted) return;
      if (categories.isEmpty) {
        _showSnack('No categories are available.');
        return;
      }

      final category = await showDialog<ReferenceCategory>(
        context: context,
        builder: (dialogContext) {
          ReferenceCategory? selected;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Save to a category'),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DropdownButtonFormField<ReferenceCategory>(
                    initialValue: selected,
                    decoration: const InputDecoration(
                      hintText: 'Choose a category',
                      border: OutlineInputBorder(),
                    ),
                    items: categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(
                              category.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      setDialogState(() => selected = value);
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: selected == null
                        ? null
                        : () => Navigator.of(dialogContext).pop(selected),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (category == null || !mounted) return;

      final bytes = await _downloadImageBytes(imageUrl);
      await ImageAssetService(_supabase).uploadImage(
        bytes,
        category,
        // Only record an original owner for images someone else sent -
        // saving your own sent image isn't "from" anyone.
        originalOwnerName: message.isMine ? null : widget.otherLoginName,
      );
      if (!mounted) return;
      _showSnack('Saved to ${category.displayName}.');
    } catch (error) {
      if (mounted) _showSnack('Unable to save image: $error');
    } finally {
      if (mounted) setState(() => _busyImageMessageId = null);
    }
  }

  Future<void> _shareImage(ChatMessage message, String imageUrl) async {
    setState(() => _busyImageMessageId = message.id);
    try {
      final bytes = await _downloadImageBytes(imageUrl);
      final mimeType = ImageAssetService.detectContentType(bytes);
      final extension = mimeType == 'image/png' ? 'png' : 'jpg';
      await ImageShareService.share(
        bytes,
        fileName: 'message_image_${message.id}.$extension',
        mimeType: mimeType,
        subject: 'Painter Reference',
      );
    } catch (error) {
      if (mounted) _showSnack('Unable to share image: $error');
    } finally {
      if (mounted) setState(() => _busyImageMessageId = null);
    }
  }

  Future<void> _saveImageToPhotos(ChatMessage message, String imageUrl) async {
    setState(() => _busyImageMessageId = message.id);
    try {
      final bytes = await _downloadImageBytes(imageUrl);
      final mimeType = ImageAssetService.detectContentType(bytes);
      final extension = mimeType == 'image/png' ? 'png' : 'jpg';
      if (!mounted) return;
      final result = await ImageDelivery.save(
        context,
        bytes,
        fileName: 'message_image_${message.id}.$extension',
      );
      if (!mounted || result.wasCancelled) return;
      _showSnack(
        result.path != null
            ? 'Image saved to ${result.path}'
            : (kIsWeb ? 'Image downloaded.' : 'Image saved to Photos.'),
      );
    } catch (error) {
      if (mounted) _showSnack('Unable to save image: $error');
    } finally {
      if (mounted) setState(() => _busyImageMessageId = null);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmBlock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${widget.otherLoginName ?? 'this user'}?'),
        content: const Text(
          'They will no longer be able to message you. You can unblock '
          'them later from settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _messagingService.blockUser(widget.otherUserId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.otherLoginName ?? 'User'} blocked.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherLoginName ?? 'Conversation'),
        actions: [
          const HomeButton(),
          PopupMenuButton<String>(
            tooltip: 'Conversation actions',
            onSelected: (value) {
              if (value == 'block') unawaited(_confirmBlock());
              if (value == 'report') unawaited(_reportPerson());
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _loadMessages(),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('No messages yet. Say hello.'));
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final previous = index > 0 ? _messages[index - 1] : null;
        final sameSenderAsPrevious =
            previous != null && previous.senderId == _messages[index].senderId;
        return _buildBubble(
          _messages[index],
          extraTopGap: sameSenderAsPrevious ? 6 : 0,
        );
      },
    );
  }

  Widget _buildBubble(ChatMessage message, {required double extraTopGap}) {
    final theme = Theme.of(context);
    final isMine = message.isMine;
    final timeLabel = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(message.createdAt.toLocal()));
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      // Long pressing anything somebody else sent offers to report it. An
      // image already had its own menu; this is what gives a written message
      // one, and images keep theirs because the inner gesture wins.
      child: GestureDetector(
        onLongPress: isMine ? null : () => _showMessageActions(message),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          margin: EdgeInsets.only(top: extraTopGap, bottom: 10),
          padding: message.imageUrl != null
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: message.imageUrl != null
                ? Border.all(color: theme.colorScheme.outlineVariant)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.imageUrl != null)
                GestureDetector(
                  onLongPress: _busyImageMessageId != null
                      ? null
                      : () => _showImageActions(message),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          message.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Icon(Icons.broken_image_outlined),
                              ),
                        ),
                      ),
                      if (_busyImageMessageId == message.id)
                        Positioned.fill(
                          child: ColoredBox(
                            color: Colors.black38,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (message.body != null)
                Padding(
                  padding: message.imageUrl != null
                      ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
                      : EdgeInsets.zero,
                  child: Text(
                    message.body!,
                    style: TextStyle(
                      color: isMine
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(
                  top: message.imageUrl != null ? 4 : 4,
                  left: message.imageUrl != null ? 4 : 0,
                ),
                child: Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine
                        ? theme.colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.7,
                          )
                        : theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: _isSending ? null : _sendImage,
              icon: const Icon(Icons.photo_outlined),
              tooltip: 'Send an image',
            ),
            Expanded(
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendText(),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _isSending ? null : _sendText,
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              tooltip: 'Send',
            ),
          ],
        ),
      ),
    );
  }
}
