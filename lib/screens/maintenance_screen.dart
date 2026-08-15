import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/impersonation_controller.dart';
import '../services/maintenance_service.dart';
import '../widgets/home_button.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late final MaintenanceService _service;
  MaintenanceSnapshot? _snapshot;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = MaintenanceService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.load();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Maintenance'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: 'Refresh maintenance data',
              icon: const Icon(Icons.refresh),
            ),
            const HomeButton(),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              Tab(icon: Icon(Icons.feedback_outlined), text: 'Feedback'),
              Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'Activity'),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 54),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    final snapshot = _snapshot!;
    return Stack(
      children: [
        TabBarView(
          children: [
            _RecordList(
              records: snapshot.users,
              emptyMessage: 'No users found.',
              title: (row) => row['email']?.toString() ?? '(no email)',
              subtitle: (row) =>
                  '${row['login_name'] == null ? '' : '${row['login_name']} • '}'
                  '${row['is_admin'] == true ? 'Administrator' : 'User'} • '
                  'Created ${_date(row['created_at'])}\n'
                  'Last sign-in ${_date(row['last_sign_in_at'])}',
              icon: (row) => row['is_admin'] == true
                  ? Icons.admin_panel_settings
                  : Icons.person_outline,
              onTap: _showUserDetails,
            ),
            _RecordList(
              records: snapshot.feedback,
              emptyMessage: 'No feedback found.',
              title: (row) =>
                  '${row['feedback_type'] ?? 'Feedback'} • ${row['status'] ?? ''}',
              subtitle: (row) =>
                  '${row['user_email'] ?? '(unknown user)'} • ${_date(row['created_at'])}\n'
                  '${row['comment'] ?? ''}',
              icon: (_) => Icons.feedback_outlined,
            ),
            _RecordList(
              records: snapshot.activity,
              emptyMessage: 'No activity found.',
              title: (row) =>
                  '${row['operation'] ?? 'Activity'} • ${row['status'] ?? ''}',
              subtitle: _activitySubtitle,
              icon: (row) => row['status'] == 'failed'
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              selectable: true,
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
      ],
    );
  }

  Future<void> _showUserDetails(Map<String, dynamic> row) async {
    final userId = row['id']?.toString();
    if (userId == null || userId.isEmpty) return;
    _showProgress('Loading user details...');
    Map<String, dynamic> user;
    try {
      user = await _service.loadUserDetails(userId);
    } catch (error) {
      if (mounted) Navigator.pop(context);
      if (mounted) _message(error.toString(), error: true);
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('User details'),
        content: SizedBox(
          width: 560,
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Email', user['email']?.toString() ?? '-'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 150,
                        child: Text(
                          'Login name',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(user['login_name']?.toString() ?? '-'),
                      ),
                      IconButton(
                        tooltip: 'Set login name',
                        onPressed: () =>
                            Navigator.pop(dialogContext, 'edit'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                _DetailRow('Auth user ID', user['id']?.toString() ?? '-'),
                _DetailRow(
                  'Administrator',
                  user['is_admin'] == true ? 'Yes' : 'No',
                ),
                _DetailRow('Phone', user['phone']?.toString() ?? '-'),
                _DetailRow('Created', _date(user['created_at'])),
                _DetailRow('Last sign-in', _date(user['last_sign_in_at'])),
                _DetailRow('Images', '${user['image_count'] ?? 0}'),
                _DetailRow(
                  'Custom categories',
                  '${user['category_count'] ?? 0}',
                ),
                _DetailRow(
                  'Stored files',
                  '${user['storage_file_count'] ?? 0}',
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (user['is_current_user'] != true)
            TextButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'impersonate'),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Impersonate'),
            ),
          if (user['is_current_user'] != true)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, 'remove'),
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('Remove User'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (action == 'remove' && mounted) await _confirmRemoveUser(user);
    if (action == 'edit' && mounted) await _editLoginName(user);
    if (action == 'impersonate' && mounted) await _impersonateUser(user);
  }

  Future<void> _impersonateUser(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;
    final currentSession = Supabase.instance.client.auth.currentSession;
    final originalRefreshToken = currentSession?.refreshToken;
    if (originalRefreshToken == null) {
      _message('No active session to restore afterward.', error: true);
      return;
    }
    _showProgress('Signing in as ${user['email'] ?? 'user'}...');
    try {
      final result = await _service.impersonate(userId);
      final targetEmail = result['email'] as String;
      final tokenHash = result['token_hash'] as String;
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.magiclink,
        tokenHash: tokenHash,
      );
      ImpersonationController.instance.begin(
        targetEmail: targetEmail,
        originalRefreshToken: originalRefreshToken,
      );
    } catch (error) {
      if (mounted) Navigator.pop(context);
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _confirmRemoveUser(Map<String, dynamic> user) async {
    final email = user['email']?.toString() ?? '';
    final userId = user['id']?.toString() ?? '';
    final controller = TextEditingController();
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
          title: const Text('Permanently remove user?'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This permanently removes $email, the login, '
                  '${user['image_count'] ?? 0} images, '
                  '${user['category_count'] ?? 0} custom categories, and '
                  '${user['storage_file_count'] ?? 0} stored files.',
                ),
                const SizedBox(height: 16),
                Text('Type exactly: $email'),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (value) =>
                      setDialogState(() => matches = value == email),
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
    _showProgress('Removing user and associated data...');
    try {
      await _service.removeUser(userId: userId, email: email);
      if (mounted) Navigator.pop(context);
      if (mounted) _message('$email was removed.');
      await _load();
    } catch (error) {
      if (mounted) Navigator.pop(context);
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _editLoginName(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;
    final controller = TextEditingController(
      text: user['login_name']?.toString() ?? '',
    );
    String? validation;
    final loginName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Set login name for ${user['email'] ?? userId}'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: 'Login name',
                hintText: 'Leave blank to clear it',
                errorText: validation,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.length > 50) {
                  setDialogState(
                    () => validation = 'Must be 50 characters or fewer.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (loginName == null || !mounted) return;
    _showProgress('Setting login name...');
    try {
      await _service.setLoginName(
        userId: userId,
        loginName: loginName.isEmpty ? null : loginName,
      );
      if (mounted) Navigator.pop(context);
      if (mounted) _message('Login name updated.');
      await _load();
    } catch (error) {
      if (mounted) Navigator.pop(context);
      if (mounted) _message(error.toString(), error: true);
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

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.records,
    required this.emptyMessage,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.selectable = false,
  });

  final List<Map<String, dynamic>> records;
  final String emptyMessage;
  final String Function(Map<String, dynamic>) title;
  final String Function(Map<String, dynamic>) subtitle;
  final IconData Function(Map<String, dynamic>) icon;
  final ValueChanged<Map<String, dynamic>>? onTap;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return Center(child: Text(emptyMessage));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = records[index];
        return Card(
          child: ListTile(
            leading: Icon(icon(row)),
            title: selectable
                ? SelectableText(title(row))
                : Text(title(row)),
            subtitle: selectable
                ? SelectableText(subtitle(row))
                : Text(subtitle(row)),
            isThreeLine: true,
            onTap: onTap == null ? null : () => onTap!(row),
          ),
        );
      },
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

String _date(dynamic value) {
  if (value == null) return '-';
  return DateTime.tryParse(value.toString())?.toLocal().toString() ??
      value.toString();
}

String _activitySubtitle(Map<String, dynamic> row) {
  final duration = row['duration_ms'];
  final durationText = duration is num ? ' • ${duration.toInt()}ms' : '';

  final lines = [
    '${row['user_email'] ?? '(unknown user)'} • '
        '${_date(row['created_at'])}$durationText',
    '${row['target_type'] ?? ''} ${row['target_id'] ?? ''}'.trim(),
  ];

  final errorMessage = row['error_message'];
  if (row['status'] == 'failed' &&
      errorMessage is String &&
      errorMessage.trim().isNotEmpty) {
    lines.add(errorMessage.trim());
  }

  return lines.where((line) => line.isNotEmpty).join('\n');
}
