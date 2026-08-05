import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart';

import '../services/admin_audit_log.dart';
import '../services/admin_service.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.service,
    required this.auditLog,
    required this.passwordRedirectUrl,
  });

  final AdminService service;
  final AdminAuditLog auditLog;
  final String? passwordRedirectUrl;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _searchController = TextEditingController();
  List<User> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.service.listUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<User> get _filteredUsers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users
        .where(
          (user) =>
              (user.email ?? '').toLowerCase().contains(query) ||
              user.id.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 420,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search users',
                    hintText: 'Email address or user ID',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: _loading ? null : _load,
                tooltip: 'Refresh users',
                icon: const Icon(Icons.refresh),
              ),
              const Spacer(),
              Text('${_filteredUsers.length} of ${_users.length} users'),
            ],
          ),
          const SizedBox(height: 20),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            _ErrorCard(message: _error!, onRetry: _load)
          else if (!_loading)
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Created')),
                        DataColumn(label: Text('Last sign-in')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: [
                        for (final user in _filteredUsers)
                          DataRow(
                            cells: [
                              DataCell(
                                SelectableText(user.email ?? '(no email)'),
                              ),
                              DataCell(Text(_date(user.createdAt))),
                              DataCell(Text(_date(user.lastSignInAt))),
                              DataCell(
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Inspect account',
                                      onPressed: user.email == null
                                          ? null
                                          : () => _showInventory(user.email!),
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Send password reset',
                                      onPressed: user.email == null
                                          ? null
                                          : () => _sendPasswordReset(user),
                                      icon: const Icon(
                                        Icons.mark_email_read_outlined,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Set password',
                                      onPressed: user.email == null
                                          ? null
                                          : () => _setPassword(user),
                                      icon: const Icon(Icons.password_outlined),
                                    ),
                                    IconButton(
                                      tooltip: 'Permanently remove user',
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      onPressed: user.email == null
                                          ? null
                                          : () => _removeUser(user.email!),
                                      icon: const Icon(
                                        Icons.delete_forever_outlined,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showInventory(String email) async {
    final inventory = await _withProgress(
      'Loading account inventory...',
      () => widget.service.inventoryForEmail(email),
    );
    if (inventory == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(inventory.email),
        content: SizedBox(
          width: 560,
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Auth user ID', inventory.user.id),
                _DetailRow('Data owner ID', inventory.dataUserId),
                _DetailRow('Created', _date(inventory.user.createdAt)),
                _DetailRow('Last sign-in', _date(inventory.user.lastSignInAt)),
                _DetailRow('Images', '${inventory.images.length}'),
                _DetailRow(
                  'Custom categories',
                  '${inventory.categories.length}',
                ),
                _DetailRow('Stored files', '${inventory.storageFileCount}'),
                for (final entry in inventory.storagePathsByBucket.entries)
                  _DetailRow('  ${entry.key}', '${entry.value.length}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPasswordReset(User user) async {
    final email = user.email!;
    final approved = await _confirm(
      title: 'Send password-reset email?',
      body: 'Supabase will send a recovery email to $email.',
      confirmLabel: 'Send Reset Email',
    );
    if (!approved) return;
    final success = await _runMutation(
      label: 'Sending recovery email...',
      action: 'users.password-reset',
      targetEmail: email,
      authUserId: user.id,
      operation: () => widget.service.sendPasswordReset(
        email,
        redirectUrl: widget.passwordRedirectUrl,
      ),
    );
    if (success) _message('Password-reset email requested for $email.');
  }

  Future<void> _setPassword(User user) async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? validation;
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Set password for ${user.email}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This directly replaces the user password. The password is '
                  'never written to the audit log.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: first,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password (12+ characters)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Repeat password',
                    errorText: validation,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.length < 12) {
                  setDialogState(
                    () => validation = 'Password must contain 12+ characters.',
                  );
                } else if (first.text != second.text) {
                  setDialogState(() => validation = 'Passwords do not match.');
                } else {
                  Navigator.pop(dialogContext, first.text);
                }
              },
              child: const Text('Set Password'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    if (password == null || !mounted) return;
    final success = await _runMutation(
      label: 'Changing password...',
      action: 'users.set-password',
      targetEmail: user.email!,
      authUserId: user.id,
      operation: () => widget.service.setPassword(user.email!, password),
    );
    if (success) _message('Password changed successfully.');
  }

  Future<void> _removeUser(String email) async {
    final inventory = await _withProgress(
      'Loading account inventory...',
      () => widget.service.inventoryForEmail(email),
    );
    if (inventory == null || !mounted) return;
    final controller = TextEditingController();
    final phrase = 'REMOVE ${inventory.email.toLowerCase()}';
    var matches = false;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: Icon(
            Icons.warning_amber,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Permanently remove account?'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This permanently deletes ${inventory.email}, the Auth login, '
                  '${inventory.images.length} images, '
                  '${inventory.categories.length} custom categories, and '
                  '${inventory.storageFileCount} stored files.',
                ),
                const SizedBox(height: 16),
                Text('Type exactly: $phrase'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (value) =>
                      setDialogState(() => matches = value == phrase),
                  decoration: const InputDecoration(labelText: 'Confirmation'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: matches
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Remove Permanently'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (approved != true || !mounted) return;
    final success = await _runMutation(
      label: 'Removing account and associated data...',
      action: 'users.remove',
      targetEmail: inventory.email,
      authUserId: inventory.user.id,
      details: inventory.toAuditDetails(),
      operation: () => widget.service.removeUser(inventory),
    );
    if (success) {
      _message('${inventory.email} and associated data were removed.');
      await _load();
    }
  }

  Future<T?> _withProgress<T>(
    String label,
    Future<T> Function() operation,
  ) async {
    _showProgress(label);
    try {
      return await operation();
    } on Object catch (error) {
      if (mounted) _message(error.toString(), error: true);
      return null;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<bool> _runMutation({
    required String label,
    required String action,
    required String targetEmail,
    required String authUserId,
    required Future<Object?> Function() operation,
    Map<String, Object?> details = const {},
  }) async {
    _showProgress(label);
    try {
      await operation();
      await widget.auditLog.write(
        action: action,
        targetEmail: targetEmail,
        authUserId: authUserId,
        result: 'success',
        details: details,
      );
      return true;
    } on Object catch (error) {
      await widget.auditLog.write(
        action: action,
        targetEmail: targetEmail,
        authUserId: authUserId,
        result: 'failed',
        details: {...details, 'error': error.toString()},
      );
      if (mounted) _message(error.toString(), error: true);
      return false;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showProgress(String label) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _date(Object? value) {
  if (value == null) return '-';
  if (value is DateTime) return value.toLocal().toString();
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toLocal().toString() ?? value.toString();
}
