import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isCreatingAccount = false;
  bool _isWorking = false;
  bool _obscurePassword = true;

  String? _errorMessage;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  Future<void> _submit() async {
    if (_isWorking) {
      return;
    }

    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      if (_isCreatingAccount) {
        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
        );

        if (!mounted) {
          return;
        }

        if (response.session == null) {
          setState(() {
            _errorMessage =
                'Your account was created. Check your email to confirm it, '
                'then return here and sign in.';
            _isCreatingAccount = false;
          });

          return;
        }
      } else {
        await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      // main.dart listens to onAuthStateChange.
      // It will automatically replace this screen after authentication.
    } on AuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Unable to authenticate: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
        });
      }
    }
  }

  void _switchMode() {
    if (_isWorking) {
      return;
    }

    setState(() {
      _isCreatingAccount = !_isCreatingAccount;
      _errorMessage = null;
    });
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Enter your email address.';
    }

    final atIndex = email.indexOf('@');
    final dotIndex = email.lastIndexOf('.');

    if (atIndex <= 0 ||
        dotIndex <= atIndex + 1 ||
        dotIndex == email.length - 1) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Enter your password.';
    }

    if (password.length < 6) {
      return 'The password must contain at least 6 characters.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 58,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Painter Reference',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isCreatingAccount
                                ? 'Create an account for your reference library.'
                                : 'Sign in to your reference library.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _emailController,
                            enabled: !_isWorking,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            autocorrect: false,
                            validator: _validateEmail,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            enabled: !_isWorking,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: _isCreatingAccount
                                ? const [AutofillHints.newPassword]
                                : const [AutofillHints.password],
                            validator: _validatePassword,
                            onFieldSubmitted: (_) {
                              _submit();
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                onPressed: _isWorking
                                    ? null
                                    : () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                              ),
                            ),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _isWorking ? null : _submit,
                            icon: _isWorking
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _isCreatingAccount
                                        ? Icons.person_add_outlined
                                        : Icons.login,
                                  ),
                            label: Text(
                              _isWorking
                                  ? 'Please wait...'
                                  : _isCreatingAccount
                                  ? 'Create Account'
                                  : 'Sign In',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _isWorking ? null : _switchMode,
                            child: Text(
                              _isCreatingAccount
                                  ? 'Already have an account? Sign in'
                                  : 'Need an account? Create one',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
