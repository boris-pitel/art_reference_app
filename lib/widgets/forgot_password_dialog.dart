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
  static const _recoveryCodeLength = 8;

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _codeFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();

  _Step _step = _Step.askEmail;
  bool _isWorking = false;
  bool _codeVerified = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _codeFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim();

  Future<void> _cancel() async {
    // verifyOTP creates a temporary authenticated recovery session. If the
    // person stops before choosing a new password, do not leave that session
    // signed in behind the dismissed dialog.
    if (_codeVerified) {
      await Supabase.instance.client.auth.signOut();
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  Future<void> _sendCode({bool validateEmail = true}) async {
    if (validateEmail && _emailFormKey.currentState?.validate() != true) {
      return;
    }

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
        _codeVerified = false;
        _codeController.clear();
        _passwordController.clear();
        _confirmController.clear();
      });
      _codeFocusNode.requestFocus();
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

  Future<void> _verifyCode() async {
    if (_isWorking || _codeVerified) return;

    final code = _codeController.text.trim();
    if (code.length != _recoveryCodeLength) {
      _codeFormKey.currentState?.validate();
      return;
    }

    setState(() {
      _isWorking = true;
      _error = null;
    });

    final auth = Supabase.instance.client.auth;

    try {
      // The password controls stay disabled until the code has proved that
      // this person owns the account.
      await auth.verifyOTP(email: _email, token: code, type: OtpType.recovery);

      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _codeVerified = true;
        _error = null;
      });
      _passwordFocusNode.requestFocus();
    } catch (error) {
      if (!mounted) return;

      final message = error.toString().toLowerCase();
      final isBadCode =
          message.contains('token') ||
          message.contains('otp') ||
          message.contains('expired') ||
          message.contains('invalid');

      setState(() {
        _isWorking = false;
        _error = isBadCode
            ? 'That code is wrong or has expired. Send yourself another if '
                  'you need to.'
            : '$error';
      });
    }
  }

  Future<void> _setPassword() async {
    if (!_codeVerified || _codeFormKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isWorking = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );

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

      setState(() {
        _isWorking = false;
        _error = '$error';
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
        constraints: const BoxConstraints(maxWidth: 500),
        child: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: _step == _Step.askEmail
                ? _buildEmailStep()
                : _buildCodeStep(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isWorking ? null : _cancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isWorking
              ? null
              : (_step == _Step.askEmail
                    ? _sendCode
                    : (_codeVerified ? _setPassword : _verifyCode)),
          child: _isWorking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _step == _Step.askEmail
                      ? 'Send code'
                      : (_codeVerified ? 'Set password' : 'Verify code'),
                ),
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
          const Text('We will email you an eight-digit code.'),
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
          Text(
            'Sent to $_email. Enter the eight-digit code to unlock the '
            'password fields.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _codeController,
            focusNode: _codeFocusNode,
            autofocus: true,
            enabled: !_codeVerified,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_recoveryCodeLength),
            ],
            onChanged: (value) {
              if (value.length == _recoveryCodeLength) _verifyCode();
            },
            decoration: const InputDecoration(
              labelText: 'Eight-digit code from the email',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final code = (value ?? '').trim();
              if (code.isEmpty) return 'Enter the code from the email.';
              if (code.length != _recoveryCodeLength) {
                return 'Enter the complete $_recoveryCodeLength-digit code.';
              }
              return null;
            },
          ),
          if (_codeVerified) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Code verified. Choose your new password.'),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            enabled: _codeVerified,
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
                onPressed: _codeVerified
                    ? () => setState(() => _obscure = !_obscure)
                    : null,
              ),
            ),
            validator: validateNewPassword,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmController,
            enabled: _codeVerified,
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
            onPressed: _isWorking
                ? null
                : () => _sendCode(validateEmail: false),
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
