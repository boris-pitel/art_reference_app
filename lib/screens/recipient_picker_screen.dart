import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/discoverable_user.dart';
import '../services/messaging_service.dart';
import 'conversation_screen.dart';

class RecipientPickerScreen extends StatefulWidget {
  const RecipientPickerScreen({
    super.key,
    required this.imageBytes,
    this.imageLabel,
  });

  final Uint8List imageBytes;
  final String? imageLabel;

  @override
  State<RecipientPickerScreen> createState() => _RecipientPickerScreenState();
}

class _RecipientPickerScreenState extends State<RecipientPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final MessagingService _messagingService;

  List<DiscoverableUser> _results = const [];
  bool _isSearching = false;
  bool _isSending = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _messagingService = MessagingService(Supabase.instance.client);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await _messagingService.searchUsers(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _sendTo(DiscoverableUser recipient) async {
    if (_isSending) return;
    setState(() => _isSending = true);
    try {
      final prepared = await _messagingService.prepareImageUpload();
      await _messagingService.uploadMessageImageBytes(
        widget.imageBytes,
        prepared,
      );
      final result = await _messagingService.sendMessage(
        recipientId: recipient.id,
        imageStoragePath: prepared.storagePath,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => ConversationScreen(
            conversationId: result.conversationId,
            otherUserId: recipient.id,
            otherLoginName: recipient.loginName,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send to friend'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
        ),
      ),
      body: Column(
        children: [
          if (widget.imageLabel != null)
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  widget.imageBytes,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text('Sending ${widget.imageLabel}'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Search by username',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _isSending
                ? const Center(child: CircularProgressIndicator())
                : _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searchController.text.trim().isEmpty
              ? 'Type a username to find someone.'
              : 'No matching users.',
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final user = _results[index];
        return ListTile(
          leading: CircleAvatar(
            child: Text(user.loginName[0].toUpperCase()),
          ),
          title: Text(user.loginName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _sendTo(user),
        );
      },
    );
  }
}
