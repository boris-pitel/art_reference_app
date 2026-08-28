import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_image_cache.dart';
import '../services/user_activity_logger.dart';
import '../widgets/home_button.dart';
import '../widgets/password_dialogs.dart';

/// Account settings, and the only place an account can be deleted.
///
/// Deletion lives behind a screen of its own rather than in a menu, because
/// both app stores require the user to be able to do it themselves and the
/// privacy policy now promises it. It is irreversible, so the confirmation
/// asks for something only the account holder can supply rather than a button
/// that can be tapped by accident.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _isDeleting = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  String get _email => _supabase.auth.currentUser?.email?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: const [HomeButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: const Text('Signed in as'),
            subtitle: Text(_email.isEmpty ? 'Unknown' : _email),
          ),
          const Divider(height: 32),
          Text('Security', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change password'),
            subtitle: const Text('You will stay signed in on this device'),
            onTap: () async {
              final changed = await showSetPasswordDialog(
                context,
                title: 'Change your password',
                requireCurrentPassword: true,
              );

              if (changed && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Your password has changed.')),
                );
              }
            },
          ),
          const Divider(height: 32),
          Text('Documents', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('https://painterreference.com/privacy'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.article_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('https://painterreference.com/terms'),
          ),
          const Divider(height: 32),
          Text(
            'Delete account',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This removes your images, categories, messages and profile, and '
            'cannot be undone. Save anything you want to keep before you '
            'continue.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isDeleting ? null : _confirmDeletion,
            icon: _isDeleting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever_outlined),
            label: Text(_isDeleting ? 'Deleting…' : 'Delete my account'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to open $url')));
      }
    }
  }

  /// Asks for the account's own email address before deleting.
  ///
  /// A typed confirmation rather than a second button: this is irreversible
  /// and unrecoverable, and it should be impossible to reach the end of by
  /// tapping through without reading.
  Future<void> _confirmDeletion() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var matches = false;

        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            final theme = Theme.of(builderContext);

            return AlertDialog(
              title: const Text('Delete your account?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Everything in your library will be permanently deleted. '
                    'This cannot be undone.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Type $_email to confirm.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) => setDialogState(() {
                      matches =
                          value.trim().toLowerCase() == _email.toLowerCase();
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: matches
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Delete permanently'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (confirmed == true) await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() => _isDeleting = true);

    try {
      await UserActivityLogger.instance.trace<void>(
        operation: 'account_delete',
        targetType: 'account',
        targetId: _supabase.auth.currentUser?.id,
        action: () async {
          final response = await _supabase.functions.invoke(
            'delete-my-account',
            body: {'confirm_email': _email},
          );

          final data = response.data;

          if (data is Map && data['deleted'] == true) return;

          throw StateError(
            data is Map && data['error'] != null
                ? data['error'].toString()
                : 'The account could not be deleted.',
          );
        },
      );

      // Deletion has to mean deletion here too. Leaving cached copies on the
      // device after the account is gone would quietly contradict what the
      // privacy policy promises.
      await AppImageCache.clear();

      // The account is gone, so the session is meaningless; signing out is what
      // returns the app to the login screen.
      await _supabase.auth.signOut();
    } catch (error) {
      if (!mounted) return;

      setState(() => _isDeleting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete the account: $error')),
      );
    }
  }
}
