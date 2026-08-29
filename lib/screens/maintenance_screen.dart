import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_status_service.dart';
import '../services/impersonation_controller.dart';
import '../services/maintenance_service.dart';
import '../services/user_activity_logger.dart';
import '../widgets/home_button.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late final MaintenanceService _service;
  late final AppStatusService _statusService;
  MaintenanceSnapshot? _snapshot;
  AppStatus _appStatus = AppStatus.available;
  List<Map<String, dynamic>> _aiLevels = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = MaintenanceService(Supabase.instance.client);
    _statusService = AppStatusService(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _service.load();
      final status = await _statusService.load();
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _appStatus = status;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showServiceStatusDialog() async {
    var enabled = _appStatus.maintenanceEnabled;
    final messageController = TextEditingController(
      text: _appStatus.message ?? '',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Service status'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: enabled,
                      title: const Text('Maintenance mode'),
                      subtitle: const Text(
                        'Blocks the app for everyone except administrators, '
                        'on web, Windows, and phone.',
                      ),
                      onChanged: (value) =>
                          setDialogState(() => enabled = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Message shown to users (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    final message = messageController.text.trim();
    messageController.dispose();

    if (saved != true || !mounted) return;

    try {
      await _service.setAppStatus(
        maintenanceEnabled: enabled,
        message: message.isEmpty ? null : message,
      );
      if (!mounted) return;
      setState(() {
        _appStatus = AppStatus(
          maintenanceEnabled: enabled,
          message: message.isEmpty ? null : message,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Maintenance mode is ON. Other users are blocked.'
                : 'Maintenance mode is OFF. The app is open to everyone.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to change service status: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Maintenance'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _showServiceStatusDialog,
              tooltip: _appStatus.maintenanceEnabled
                  ? 'Maintenance mode is ON'
                  : 'Service status',
              icon: Icon(
                _appStatus.maintenanceEnabled
                    ? Icons.build_circle
                    : Icons.build_circle_outlined,
                color: _appStatus.maintenanceEnabled
                    ? Colors.orange.shade300
                    : null,
              ),
            ),
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
              Tab(icon: Icon(Icons.tune), text: 'Levels'),
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
            _buildLevelsTab(),
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
        // Scrollable because this panel is taller than a phone. Without it the
        // content overflows and the buttons are painted on top of the last
        // few rows, which is unreadable rather than merely cramped.
        scrollable: true,
        title: const Text('User details'),
        content: ConstrainedBox(
          // A maximum rather than a fixed width. 560 was wider than the screen
          // it had to fit on, so a phone was being asked to lay out something
          // that could not fit and the text wrapped one character at a time.
          constraints: const BoxConstraints(maxWidth: 560),
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
                        onPressed: () => Navigator.pop(dialogContext, 'edit'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(
                        width: 150,
                        child: Text(
                          'AI level',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(child: Text(_describeLevel(user))),
                      IconButton(
                        tooltip: 'Set AI level',
                        onPressed: () => Navigator.pop(dialogContext, 'level'),
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
                _DetailRow('AI edits today', '${user['ai_edits_today'] ?? 0}'),
                _DetailRow(
                  'AI edits this month',
                  '${user['ai_edits_this_month'] ?? 0}',
                ),
                _DetailRow(
                  'AI edits ever',
                  // The failure count matters: a person whose edits keep
                  // failing looks like a heavy user from the total alone.
                  '${user['ai_edits_all_time'] ?? 0}'
                      '${(user['ai_edits_failed'] ?? 0) == 0 ? '' : ' (${user['ai_edits_failed']} failed)'}',
                ),
              ],
            ),
          ),
        ),
        actions: [
          // Somebody locked out of their password used to mean a trip to the
          // Supabase dashboard, or an administrator setting it by hand and
          // then having to tell them what it was. This sends them a link and
          // lets them choose it themselves, which is the only version where
          // nobody else ever knows the password.
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'reset_password'),
            icon: const Icon(Icons.lock_reset_outlined),
            label: const Text('Send password reset'),
          ),
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
    if (action == 'level' && mounted) await _editAiLevel(user);
    if (action == 'impersonate' && mounted) await _impersonateUser(user);
    if (action == 'reset_password' && mounted) await _sendPasswordReset(user);
  }

  /// Emails a reset link to somebody who cannot get in.
  ///
  /// Confirmed first, because it lands unannounced in their inbox and a
  /// password reset nobody asked for is alarming rather than helpful.
  Future<void> _sendPasswordReset(Map<String, dynamic> user) async {
    final email = user['email']?.toString().trim() ?? '';
    if (email.isEmpty) {
      _message('That account has no email address.', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send a password reset?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            '$email will be emailed a link that lets them choose a new '
            'password. Their current one keeps working until they do.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);

      UserActivityLogger.instance.record(
        operation: 'password_reset_sent',
        status: 'succeeded',
        targetType: 'account',
        details: {'for': email},
      );

      if (mounted) _message('A reset link is on its way to $email.');
    } catch (error) {
      UserActivityLogger.instance.record(
        operation: 'password_reset_sent',
        status: 'failed',
        targetType: 'account',
        details: {'for': email},
        error: error,
      );

      if (mounted) _message('Could not send it: $error', error: true);
    }
  }

  /// Says what the person actually gets, not just what is stored.
  ///
  /// A null level is the common case and means "whatever the default is", which
  /// reads as an empty field unless it is spelled out. An administrator with no
  /// level set is unlimited, and showing a blank there would be actively
  /// misleading.
  String _describeLevel(Map<String, dynamic> user) {
    final stored = user['ai_level'];
    final label = stored is int ? _levelLabel(stored) : 'Unknown';

    // Stated rather than left implied: an administrator is unlimited whatever
    // level they hold, so showing only the stored level would be wrong.
    return user['is_admin'] == true ? '$label — unlimited (admin)' : label;
  }

  String _levelLabel(int level) {
    for (final entry in _aiLevels) {
      if (entry['level'] == level) {
        return '$level · ${entry['display_name'] ?? ''}';
      }
    }
    return '$level';
  }

  Future<void> _editAiLevel(Map<String, dynamic> user) async {
    final userId = user['id']?.toString();
    if (userId == null || userId.isEmpty) return;

    if (_aiLevels.isEmpty) await _loadAiLevels();
    if (!mounted) return;

    final current = user['ai_level'];
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('AI level for ${user['email'] ?? 'this user'}'),
        children: [
          for (final entry in _aiLevels)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(dialogContext, entry['level'] as int),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entry['level'] == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(
                  '${entry['level']} · ${entry['display_name'] ?? ''}',
                ),
                subtitle: Text(
                  entry['tier'] == 'unlimited'
                      ? 'No limit'
                      : '${entry['per_user_daily']} a day · '
                            '${entry['per_user_monthly']} a month',
                ),
              ),
            ),
        ],
      ),
    );

    if (chosen == null || !mounted) return;

    _showProgress('Updating level...');
    try {
      await _service.setUserAiLevel(userId: userId, level: chosen);
      if (mounted) Navigator.pop(context);
      if (mounted) _message('AI level updated.');
      await _load();
    } catch (error) {
      if (mounted) Navigator.pop(context);
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Widget _buildLevelsTab() {
    if (_aiLevels.isEmpty) {
      // Loaded on first view rather than with the rest of the screen: most
      // visits to Maintenance are not about levels.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _aiLevels.isEmpty && !_loading) _loadAiLevels();
      });
      return const Center(child: CircularProgressIndicator());
    }

    final globalDaily = _aiLevels.first['global_daily'];
    final defaultLevel = _aiLevels.first['default_level'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Limit across all users'),
            subtitle: Text(
              '$globalDaily AI edits a day for everyone combined.\n'
              'This is the ceiling that caps what a bad day can cost, '
              'whatever any individual level allows.',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Change the service limit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  _editGlobalLimit(globalDaily is int ? globalDaily : 0),
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final level in _aiLevels)
          Card(
            child: ListTile(
              leading: Icon(
                level['tier'] == 'unlimited'
                    ? Icons.all_inclusive
                    : Icons.workspace_premium_outlined,
              ),
              title: Row(
                children: [
                  Text('${level['level']} · ${level['display_name'] ?? ''}'),
                  if (level['level'] == defaultLevel) ...[
                    const SizedBox(width: 8),
                    const Chip(
                      label: Text('Default'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              subtitle: Text(
                level['tier'] == 'unlimited'
                    ? 'No limit · ${level['members']} on this level'
                    : '${level['per_user_daily']} a day · '
                          '${level['per_user_monthly']} a month · '
                          '${level['members']} on this level',
              ),
              trailing: level['tier'] == 'unlimited'
                  // Nothing to edit: unlimited is the absence of a limit, and
                  // offering numbers here would imply it has some.
                  ? null
                  : IconButton(
                      tooltip: 'Change limits',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editLevelLimits(level),
                    ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Anyone without a level set follows the default. '
          'Administrators are never refused.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _editLevelLimits(Map<String, dynamic> level) async {
    final daily = TextEditingController(
      text: '${level['per_user_daily'] ?? 0}',
    );
    final monthly = TextEditingController(
      text: '${level['per_user_monthly'] ?? 0}',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${level['display_name']} limits'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: daily,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'AI edits a day',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: monthly,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'AI edits a month',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final perDay = int.tryParse(daily.text.trim());
    final perMonth = int.tryParse(monthly.text.trim());
    if (perDay == null || perMonth == null || perDay < 0 || perMonth < 0) {
      _message('Limits must be whole numbers.', error: true);
      return;
    }
    // Checked here as well as on the server, so the reason arrives before the
    // round trip rather than after it.
    if (perDay > perMonth) {
      _message(
        'The daily limit cannot be higher than the monthly one.',
        error: true,
      );
      return;
    }

    try {
      await _service.setAiLevelLimits(
        tier: level['tier']?.toString() ?? '',
        perUserDaily: perDay,
        perUserMonthly: perMonth,
      );
      await _loadAiLevels();
      if (mounted) _message('Limits updated.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _editGlobalLimit(int current) async {
    final controller = TextEditingController(text: '$current');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limit across all users'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The most AI edits the whole service will perform in one day. '
              'Reaching it stops everyone, so it is the number that decides '
              'what the worst possible day costs.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'AI edits a day, all users',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 0) {
      _message('The service limit must be a whole number.', error: true);
      return;
    }

    try {
      await _service.setGlobalAiLimit(value);
      await _loadAiLevels();
      if (mounted) _message('Service limit updated.');
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
  }

  Future<void> _loadAiLevels() async {
    try {
      final levels = await _service.loadAiLevels();
      if (mounted) setState(() => _aiLevels = levels);
    } catch (error) {
      if (mounted) _message(error.toString(), error: true);
    }
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
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
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
            title: selectable ? SelectableText(title(row)) : Text(title(row)),
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

/// One line naming the device a log entry came from, so a fault that only
/// occurs on particular hardware can be attributed without asking the user.
///
/// Returns null for entries recorded before device details were captured.
String? _deviceSummary(Map<String, dynamic> row) {
  final details = row['details'];
  if (details is! Map) return null;

  final device = details['device'];
  if (device is! Map || device.isEmpty) return null;

  final platform = row['platform']?.toString();

  final parts = <String>[
    if (platform != null && platform.isNotEmpty) platform,
    // Native reports the manufacturer and model directly; the web build gets
    // the model from Client Hints, since the user agent masks it.
    [
      device['manufacturer'],
      device['model'],
    ].whereType<String>().where((value) => value.isNotEmpty).join(' '),
    [
          device['android_version'],
          device['system_version'],
          device['platform_version'],
        ].whereType<String>().where((value) => value.isNotEmpty).firstOrNull ??
        '',
    if (device['screen'] is String) device['screen'] as String,
  ].where((value) => value.isNotEmpty).toList();

  if (parts.isEmpty) {
    // Nothing identifying resolved, but the raw agent is better than silence.
    final userAgent = device['user_agent'];
    return userAgent is String ? userAgent : null;
  }

  return parts.join(' • ');
}

String _activitySubtitle(Map<String, dynamic> row) {
  final duration = row['duration_ms'];
  final durationText = duration is num ? ' • ${duration.toInt()}ms' : '';

  final lines = [
    '${row['user_email'] ?? '(unknown user)'} • '
        '${_date(row['created_at'])}$durationText',
    '${row['target_type'] ?? ''} ${row['target_id'] ?? ''}'.trim(),
  ];

  final device = _deviceSummary(row);
  if (device != null) {
    lines.add(device);
  }

  final errorMessage = row['error_message'];
  if (row['status'] == 'failed' &&
      errorMessage is String &&
      errorMessage.trim().isNotEmpty) {
    lines.add(errorMessage.trim());
  }

  return lines.where((line) => line.isNotEmpty).join('\n');
}
