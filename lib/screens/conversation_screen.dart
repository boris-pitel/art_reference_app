import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../services/messaging_service.dart';
import '../widgets/home_button.dart';

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
  RealtimeChannel? _channel;

  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _messagingService = MessagingService(_supabase);
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
            },
            itemBuilder: (context) => const [
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
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  message.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Icon(Icons.broken_image_outlined),
                  ),
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
