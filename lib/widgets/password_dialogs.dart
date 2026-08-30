import 'package:flutter/foundation.dart';
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

/// Asks for an address and sends a reset link to it.
///
/// Deliberately says the same thing whether or not the address has an account.
/// Answering honestly would turn this box into a way of discovering who has
/// registered, which is a question no stranger should be able to ask.
Future<void> showForgotPasswordDialog(BuildContext context) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var isSending = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Reset your password'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'We will email you a link that lets you choose a new one.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = (value ?? '').trim();
                    if (email.isEmpty) return 'Enter your email address.';
                    if (!email.contains('@')) return 'Enter a valid address.';
                    return null;
                  },
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
            onPressed: isSending
                ? null
                : () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: isSending
                ? null
                : () async {
                    if (formKey.currentState?.validate() != true) return;

                    setDialogState(() {
                      isSending = true;
                      error = null;
                    });

                    final email = controller.text.trim();

                    try {
                      await Supabase.instance.client.auth.resetPasswordForEmail(
                        email,
                        // Mobile has no origin to come back to, so the link
                        // returns through the scheme the app registers. On web
                        // this is left to the project's own site URL.
                        redirectTo: _resetRedirect,
                      );

                      UserActivityLogger.instance.record(
                        operation: 'password_reset_requested',
                        status: 'succeeded',
                        targetType: 'account',
                      );

                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();

                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'If that address has an account, a reset link is '
                            'on its way.',
                          ),
                          duration: Duration(seconds: 5),
                        ),
                      );
                    } catch (sendError) {
                      UserActivityLogger.instance.record(
                        operation: 'password_reset_requested',
                        status: 'failed',
                        targetType: 'account',
                        error: sendError,
                      );

                      setDialogState(() {
                        isSending = false;
                        error = 'Could not send the email: $sendError';
                      });
                    }
                  },
            child: isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send link'),
          ),
        ],
      ),
    ),
  );

  controller.dispose();
}

/// Where a reset link comes back to.
///
/// Only Android and iOS register com.painterreference.app://, and this used to
/// send every platform that was not web to that scheme — so a link opened on
/// Windows redirected to something Windows cannot handle and the browser showed
/// an empty page. The reset was never lost, but there was nowhere to type the
/// new password.
///
/// Desktop is sent to the web app instead, which is the same application and
/// can complete the reset in the browser; the new password then signs them in
/// on Windows. Web passes null and lets Supabase use its own site URL, because
/// the page the link opens is already the app.
String? get _resetRedirect {
  if (kIsWeb) return null;

  final isMobile =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  return isMobile
      ? 'com.painterreference.app://login-callback'
      : 'https://painterreference.com';
}

/// Takes a new password and sets it.
///
/// Used by somebody who followed a reset link and by somebody who simply wants
/// to change it from their account screen — the same two fields either way,
/// because the difference between those situations is not one the person
/// typing needs explained to them.
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
