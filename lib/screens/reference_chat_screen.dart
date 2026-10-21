import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../services/image_asset_service.dart';
import '../services/reference_chat_service.dart';

/// A reference always reopens the same server conversation, including when
/// entered through an attachment. Drafts are account-scoped on this device.
class ReferenceChatScreen extends StatefulWidget {
  const ReferenceChatScreen({
    super.key,
    required this.referenceId,
    required this.selectedImageId,
    this.service,
  });
  final String referenceId;
  final String selectedImageId;
  final ReferenceChatService? service;
  @override
  State<ReferenceChatScreen> createState() => _ReferenceChatScreenState();
}

class _ReferenceChatScreenState extends State<ReferenceChatScreen> {
  final _text = TextEditingController();
  late final _service = widget.service ?? ReferenceChatService();
  final _scroll = ScrollController();
  final _saving = <String>{};
  final _selected = <String>{};
  late final String? _account = Supabase.instance.client.auth.currentUser?.id;
  StreamSubscription<AuthState>? _auth;
  Timer? _draftTimer;
  List<Map<String, dynamic>> _turns = [], _images = [];
  bool _loading = true, _busy = false;
  String? _error, _requestId;
  bool get _allowed =>
      _account != null &&
      Supabase.instance.client.auth.currentUser?.id == _account &&
      Supabase.instance.client.auth.currentUser?.appMetadata['is_admin'] ==
          true;
  String get _draftKey =>
      'reference_chat_draft_$_account/${widget.referenceId}';

  @override
  void initState() {
    super.initState();
    _selected.add(widget.selectedImageId);
    _auth = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_draftKey);
      if (raw != null && mounted && _allowed) {
        final draft = jsonDecode(raw) as Map;
        _text.text = draft['text'] as String? ?? '';
        _requestId = draft['requestId'] as String?;
        final savedImages = (draft['images'] as List).cast<String>();
        _selected
          ..clear()
          ..addAll(savedImages.take(4));
        // Opening a different attachment explicitly selects that attachment.
        if (widget.selectedImageId != widget.referenceId &&
            !_selected.contains(widget.selectedImageId)) {
          if (_selected.length == 4) _selected.remove(_selected.last);
          _selected.add(widget.selectedImageId);
          _requestId = null;
        }
      }
    } catch (_) {
      /* A damaged draft must not prevent loading saved messages. */
    }
    if (!mounted) return;
    _text.addListener(_changed);
    await _load();
  }

  void _changed() {
    _requestId = null;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 250), _persistDraft);
  }

  Future<void> _persistDraft() async {
    final value = jsonEncode({
      'text': _text.text,
      'images': _selected.toList(),
      'requestId': _requestId,
    });
    await (await SharedPreferences.getInstance()).setString(_draftKey, value);
  }

  void _apply(Map<String, dynamic> data) {
    _turns = (data['turns'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _images = (data['images'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    _selected.removeWhere((id) => !_images.any((image) => image['id'] == id));
  }

  Future<void> _load() async {
    if (!_allowed) return;
    try {
      final data = await _service.call(widget.referenceId, 'load');
      if (!mounted || !_allowed) return;
      final turns = data['turns'] as List;
      if (_requestId != null && turns.any((turn) => turn['id'] == _requestId)) {
        // The server finished a send whose network reply was lost (or the
        // process was killed). Do not offer the same draft as a new message.
        _text.removeListener(_changed);
        _text.clear();
        _text.addListener(_changed);
        _requestId = null;
        _selected.clear();
        await _persistDraft();
        if (!mounted) return;
      }
      setState(() {
        _apply(data);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted && _allowed) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _send() async {
    if (!_allowed || _busy || _text.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _requestId ??= const Uuid().v4();
    _draftTimer?.cancel();
    try {
      await _persistDraft();
      final data = await _service.call(widget.referenceId, 'send', {
        'requestId': _requestId,
        'text': _text.text.trim(),
        'imageIds': _selected.toList(),
      });
      if (!mounted || !_allowed) return;
      _text.removeListener(_changed);
      _text.clear();
      _text.addListener(_changed);
      _requestId = null;
      _selected.clear();
      await _persistDraft();
      if (!mounted) return;
      setState(() => _apply(data));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error) {
      if (mounted && _allowed) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(Map image) async {
    final id = image['id'] as String;
    if (!_allowed || image['savedImageId'] != null || !_saving.add(id)) return;
    setState(() {});
    try {
      final response = await http
          .get(Uri.parse(image['url'] as String))
          .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw StateError(
          'Could not download this image. Reopen the chat and try again.',
        );
      }
      if (!_allowed) return;
      final savedId = await ImageAssetService(
        Supabase.instance.client,
      ).uploadAssociatedImage(response.bodyBytes, widget.referenceId);
      if (!_allowed) return;
      final data = await _service.call(widget.referenceId, 'markSaved', {
        'generatedId': id,
        'savedImageId': savedId,
      });
      if (mounted && _allowed) setState(() => _apply(data));
    } catch (error) {
      if (mounted && _allowed) setState(() => _error = '$error');
    } finally {
      _saving.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _chooseImages() async {
    final chosen = Set<String>.from(_selected);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Discuss images (up to 4)'),
          content: SizedBox(
            width: 440,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final image in _images)
                  CheckboxListTile(
                    secondary: _thumbnail(image['url'] as String),
                    title: Text(image['label'] as String),
                    value: chosen.contains(image['id']),
                    onChanged: (value) => update(() {
                      if (value == true && chosen.length < 4) {
                        chosen.add(image['id'] as String);
                      } else if (value == false) {
                        chosen.remove(image['id']);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: const Text('Use selected'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted || !_allowed) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(result);
      _requestId = null;
    });
    await _persistDraft();
  }

  Widget _thumbnail(String url) => Image.network(
    url,
    width: 56,
    height: 56,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
  );

  Widget _message(
    String label,
    String text,
    List images, {
    bool generated = false,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (text.isNotEmpty) SelectableText(text),
          for (final image in images)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: Stack(
                          children: [
                            InteractiveViewer(
                              child: Image.network(image['url'] as String),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Image.network(
                      image['url'] as String,
                      height: generated ? 260 : 110,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text(
                        'Image unavailable. Reopen chat to refresh.',
                      ),
                    ),
                  ),
                  if (generated)
                    TextButton.icon(
                      onPressed:
                          image['savedImageId'] != null ||
                              _saving.contains(image['id']) ||
                              _busy
                          ? null
                          : () => _save(image as Map),
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        image['savedImageId'] != null
                            ? 'Saved'
                            : _saving.contains(image['id'])
                            ? 'Saving…'
                            : 'Save to reference',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Administrator access required.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Reference chat')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (!_loading && _turns.isEmpty)
                        const Text(
                          'Ask about this reference or select its attachments. This conversation is saved. Messages and selected images are sent to OpenAI when you tap Send.',
                        ),
                      for (final turn in _turns) ...[
                        _message(
                          'You',
                          turn['text'] as String,
                          turn['images'] as List? ?? [],
                        ),
                        _message(
                          'ChatGPT',
                          turn['answer'] as String,
                          turn['generated'] as List? ?? [],
                          generated: true,
                        ),
                      ],
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('ChatGPT is responding…'),
                        ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        if (!_busy)
                          TextButton(
                            onPressed: _load,
                            child: const Text('Reload'),
                          ),
                      ],
                    ),
                  ),
                if (_selected.isNotEmpty)
                  SizedBox(
                    height: 68,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final image in _images.where(
                          (image) => _selected.contains(image['id']),
                        ))
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Tooltip(
                              message: image['label'] as String,
                              child: _thumbnail(image['url'] as String),
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Select reference or attachments',
                        onPressed: _busy || _loading ? null : _chooseImages,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _text,
                          enabled: !_busy && !_loading,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 8000,
                          decoration: const InputDecoration(
                            hintText: 'Ask about the selected images…',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Send',
                        onPressed: _busy || _loading ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _text.removeListener(_changed);
    unawaited(_persistDraft());
    _auth?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }
}
