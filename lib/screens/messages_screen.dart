import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/conversation_summary.dart';
import '../services/messaging_service.dart';
import '../widgets/home_button.dart';
import 'conversation_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final MessagingService _messagingService;
  List<ConversationSummary> _conversations = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _messagingService = MessagingService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final conversations = await _messagingService.listConversations();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load messages.\n$error';
      });
    }
  }

  Future<void> _openConversation(ConversationSummary conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ConversationScreen(
          conversationId: conversation.conversationId,
          otherUserId: conversation.otherUserId,
          otherLoginName: conversation.otherLoginName,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          const HomeButton(),
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
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
              FilledButton(onPressed: _load, child: const Text('Try Again')),
            ],
          ),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return const Center(
        child: Text(
          'No conversations yet.\nUse "Send to friend" on an image to '
          'start one.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: _conversations.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        final name = conversation.otherLoginName ?? 'Unknown user';
        return ListTile(
          leading: CircleAvatar(
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
          ),
          title: Text(name),
          subtitle: Text(
            conversation.lastMessagePreview ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: conversation.unreadCount > 0
              ? CircleAvatar(
                  radius: 10,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    '${conversation.unreadCount}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                )
              : null,
          onTap: () => _openConversation(conversation),
        );
      },
    );
  }
}
