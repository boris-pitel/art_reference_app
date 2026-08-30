import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/user_activity_logger.dart';
import 'password_dialogs.dart';

/// Resetting a forgotten password with a code rather than a link.
///
/// A link has to come back to a particular place, and that turned out to be
/// the whole difficulty. The secret that redeems it is written on the device
/// that asked, so a reset requested on a computer and opened on a phone cannot
/// complete — and did not, silently, leaving somebody on the home screen
/// believing they had changed a password they had not. Sending desktop links
/// to the web app only moved the failure, since a browser has no more access
/// to the desktop app's secret than the phone did.
///
/// A code travels in the message and is typed in wherever the person happens
/// to be. Nothing has to return anywhere, so there is no device to get wrong:
/// no deep link, no redirect URL, no browser hand-off, and no blank page. It
/// is also what people now expect, because banks and everything else work this
/// way.
class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key});

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

enum _Step { askEmail, enterCode }

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();

  _Step _step = _Step.askEmail;
  bool _isWorking = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim();

  Future<void> _sendCode() async {
    if (_emailFormKey.currentState?.validate() != true) return;

    setState(() {
      _isWorking = true;
      _error = null;
    });

    try {
      // No redirect: the message carries a code, and nothing needs to come
      // back to this device or any other.
      await Supabase.instance.client.auth.resetPasswordForEmail(_email);

      UserActivityLogger.instance.record(
        operation: 'password_reset_requested',
        status: 'succeeded',
        targetType: 'account',
      );

      if (!mounted) return;
      setState(() {
        _step = _Step.enterCode;
        _isWorking = false;
      });
    } catch (error) {
      UserActivityLogger.instance.record(
        operation: 'password_reset_requested',
        status: 'failed',
        targetType: 'account',
        error: error,
      );

      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _error = 'Could not send the code: $error';
      });
    }
  }

  Future<void> _verifyAndSet() async {
    if (_codeFormKey.currentState?.validate() != true) return;

    setState(() {
      _isWorking = true;
      _error = null;
    });

    final auth = Supabase.instance.client.auth;

    try {
      // The code both proves who they are and signs them in, which is what
      // makes the password change below permissible.
      await auth.verifyOTP(
        email: _email,
        token: _codeController.text.trim(),
        type: OtpType.recovery,
      );

      await auth.updateUser(UserAttributes(password: _passwordController.text));

      UserActivityLogger.instance.record(
        operation: 'password_reset_completed',
        status: 'succeeded',
        targetType: 'account',
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      UserActivityLogger.instance.record(
        operation: 'password_reset_completed',
        status: 'failed',
        targetType: 'account',
        error: error,
      );

      if (!mounted) return;

      // A wrong or stale code answers with something about a token, which
      // means nothing to the person who just typed six digits.
      final message = error.toString().toLowerCase();
      final isBadCode =
          message.contains('token') ||
          message.contains('otp') ||
          message.contains('expired') ||
          message.contains('invalid');

      setState(() {
        _isWorking = false;
        _error = isBadCode
            ? 'That code is wrong or has expired. Codes last an hour; send '
                  'yourself another if you need to.'
            : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _step == _Step.askEmail ? 'Reset your password' : 'Enter your code',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: _step == _Step.askEmail ? _buildEmailStep() : _buildCodeStep(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isWorking ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isWorking
              ? null
              : (_step == _Step.askEmail ? _sendCode : _verifyAndSet),
          child: _isWorking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_step == _Step.askEmail ? 'Send code' : 'Set password'),
        ),
      ],
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We will email you a six-digit code.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
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
          _buildError(),
        ],
      ),
    );
  }

  Widget _buildCodeStep() {
    return Form(
      key: _codeFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sent to $_email. Enter the code and choose a new password.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(
              labelText: 'Six-digit code',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final code = (value ?? '').trim();
              if (code.isEmpty) return 'Enter the code from the email.';
              if (code.length < 6) return 'The code is six digits.';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'New password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: validateNewPassword,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Repeat it',
              border: OutlineInputBorder(),
            ),
            validator: (value) => value == _passwordController.text
                ? null
                : 'The two do not match.',
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isWorking ? null : _sendCode,
            child: const Text('Send another code'),
          ),
          _buildError(),
        ],
      ),
    );
  }

  Widget _buildError() {
    if (_error == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// Shows the reset flow. True when a password was actually changed.
Future<bool> showForgotPasswordDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ForgotPasswordDialog(),
  );

  return changed ?? false;
}
