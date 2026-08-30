import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/user_activity_logger.dart';

/// The shortest password Supabase will accept for this project.
const int minimumPasswordLength = 6;

String? validateNewPassword(String? value) {
  final password = value ?? '';

  if (password.isEmpty) return 'Enter a password.';
  if (password.length < minimumPasswordLength) {
    return 'The password must contain at least $minimumPasswordLength characters.';
  }

  return null;
}

/// Takes a new password and sets it.
///
/// The difference between "I forgot it" and "I want to change it" is not one
/// the person typing needs explained to them.
Future<bool> showSetPasswordDialog(
  BuildContext context, {
  required String title,
  String? subtitle,

  /// Whether to ask for the password being replaced.
  ///
  /// True when somebody is changing a password they still know, which is the
  /// case where it matters: without it, anyone holding an unlocked phone with
  /// the app signed in could take the account away from its owner.
  ///
  /// False after a reset link, where the link is the proof of identity and
  /// asking a person who has forgotten their password for their password
  /// would defeat the entire purpose.
  bool requireCurrentPassword = false,
}) async {
  final currentController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var isSaving = false;
  var obscure = true;
  String? error;

  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) ...[
                  Text(subtitle),
                  const SizedBox(height: 16),
                ],
                if (requireCurrentPassword) ...[
                  TextFormField(
                    controller: currentController,
                    autofocus: true,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').isEmpty
                        ? 'Enter your current password.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: passwordController,
                  autofocus: !requireCurrentPassword,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'New password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: validateNewPassword,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmController,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Repeat it',
                    border: OutlineInputBorder(),
                  ),
                  // Asked twice because a password typed once and mistyped is
                  // a lockout that only shows up at the next sign-in, by which
                  // time nobody remembers what they meant to type.
                  validator: (value) => value == passwordController.text
                      ? null
                      : 'The two do not match.',
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving
                ? null
                : () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: isSaving
                ? null
                : () async {
                    if (formKey.currentState?.validate() != true) return;

                    setDialogState(() {
                      isSaving = true;
                      error = null;
                    });

                    final auth = Supabase.instance.client.auth;

                    try {
                      if (requireCurrentPassword) {
                        final email = auth.currentUser?.email?.trim() ?? '';
                        if (email.isEmpty) {
                          throw StateError(
                            'You must be signed in to change your password.',
                          );
                        }

                        // Proves the person at the keyboard is the account
                        // holder and not somebody who picked up an unlocked
                        // phone. Signing in again is the only way to check a
                        // password from here — the server never hands one back
                        // to be compared.
                        await auth.signInWithPassword(
                          email: email,
                          password: currentController.text,
                        );
                      }

                      await auth.updateUser(
                        UserAttributes(password: passwordController.text),
                      );

                      UserActivityLogger.instance.record(
                        operation: 'password_changed',
                        status: 'succeeded',
                        targetType: 'account',
                        details: {'verified': requireCurrentPassword},
                      );

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                    } catch (saveError) {
                      UserActivityLogger.instance.record(
                        operation: 'password_changed',
                        status: 'failed',
                        targetType: 'account',
                        error: saveError,
                      );

                      // Supabase answers a wrong password with "Invalid login
                      // credentials", which reads as though the whole account
                      // is wrong rather than the one field that is.
                      final wrongCurrent =
                          requireCurrentPassword &&
                          saveError is AuthException &&
                          saveError.message.toLowerCase().contains('invalid');

                      setDialogState(() {
                        isSaving = false;
                        error = wrongCurrent
                            ? 'That is not your current password.'
                            : '$saveError';
                      });
                    }
                  },
            child: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    ),
  );

  currentController.dispose();
  passwordController.dispose();
  confirmController.dispose();

  return saved ?? false;
}
