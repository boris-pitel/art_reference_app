import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/discoverable_user.dart';
import '../services/messaging_service.dart';
import '../widgets/home_button.dart';

class MessagingSettingsScreen extends StatefulWidget {
  const MessagingSettingsScreen({super.key});

  @override
  State<MessagingSettingsScreen> createState() =>
      _MessagingSettingsScreenState();
}

class _MessagingSettingsScreenState extends State<MessagingSettingsScreen> {
  late final MessagingService _messagingService;

  bool _isLoading = true;
  bool _isDiscoverable = true;
  bool _isSavingToggle = false;
  List<BlockedUser> _blockedUsers = const [];
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
      final results = await Future.wait([
        _messagingService.getDiscoverable(),
        _messagingService.listBlockedUsers(),
      ]);
      if (!mounted) return;
      setState(() {
        _isDiscoverable = results[0] as bool;
        _blockedUsers = results[1] as List<BlockedUser>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load privacy settings.\n$error';
      });
    }
  }

  Future<void> _toggleDiscoverable(bool value) async {
    setState(() {
      _isDiscoverable = value;
      _isSavingToggle = true;
    });
    try {
      await _messagingService.setDiscoverable(value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDiscoverable = !value);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _isSavingToggle = false);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    try {
      await _messagingService.unblockUser(user.id);
      if (!mounted) return;
      setState(() {
        _blockedUsers = _blockedUsers.where((u) => u.id != user.id).toList();
      });
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
        title: const Text('Privacy and blocking'),
        actions: const [HomeButton()],
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
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Let people find me by username'),
          subtitle: const Text(
            'When off, only people you\'ve already messaged can find you.',
          ),
          value: _isDiscoverable,
          onChanged: _isSavingToggle ? null : _toggleDiscoverable,
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Blocked users',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (_blockedUsers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('You haven\'t blocked anyone.'),
          )
        else
          ..._blockedUsers.map(
            (user) => ListTile(
              leading: CircleAvatar(
                child: Text(
                  (user.loginName?.isNotEmpty ?? false)
                      ? user.loginName![0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(user.loginName ?? 'Unknown user'),
              trailing: TextButton(
                onPressed: () => _unblock(user),
                child: const Text('Unblock'),
              ),
            ),
          ),
      ],
    );
  }
}
