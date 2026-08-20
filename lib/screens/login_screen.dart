import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../services/google_sign_in_service.dart';
import '../services/user_activity_logger.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _loginNameController = TextEditingController();

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
    _loginNameController.dispose();

    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      await GoogleSignInService.signIn();

      // On web the page has already navigated away by now, so this records
      // only the platforms that return here. Web sign-ins are logged by the
      // auth listener in main.dart instead, which runs after the redirect.
      if (_supabase.auth.currentUser != null) {
        UserActivityLogger.instance.record(
          operation: 'login',
          status: 'succeeded',
          targetType: 'account',
          targetId: _supabase.auth.currentUser?.id,
          details: const {'provider': 'google'},
        );
      }

      // main.dart listens to onAuthStateChange and replaces this screen once
      // the session lands.
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Google sign-in failed: $error');
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
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
    final loginName = _loginNameController.text.trim();
    final creatingAccount = _isCreatingAccount;
    AppUserProfile? registeredProfile;

    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });

    try {
      if (creatingAccount) {
        if (loginName.isNotEmpty && !await _isLoginNameAvailable(loginName)) {
          if (mounted) {
            setState(() {
              _errorMessage =
                  'That login name is already in use. Choose another name or leave it empty.';
            });
          }
          return;
        }
        final response = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: loginName.isEmpty ? null : {'login_name': loginName},
        );

        final registeredUser = response.user;
        registeredProfile = registeredUser == null
            ? null
            : AppUserProfile.fromAuthUser(registeredUser);

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
      UserActivityLogger.instance.record(
        operation: creatingAccount ? 'account_create' : 'login',
        status: 'succeeded',
        targetType: 'account',
        targetId: _supabase.auth.currentUser?.id,
        details: creatingAccount && registeredProfile?.loginName != null
            ? {'login_name': registeredProfile!.loginName}
            : const {},
      );

      // main.dart listens to onAuthStateChange.
      // It will automatically replace this screen after authentication.
    } on AuthException catch (error) {
      var message = error.message;
      if (creatingAccount && loginName.isNotEmpty) {
        try {
          if (!await _isLoginNameAvailable(loginName)) {
            message =
                'That login name is already in use. Choose another name or leave it empty.';
          }
        } catch (_) {
          // Preserve the original authentication error if availability cannot
          // be checked while handling it.
        }
      }
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = message;
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

  String? _validateLoginName(String? value) {
    final loginName = value?.trim() ?? '';
    if (loginName.length > 50) {
      return 'Login name cannot exceed 50 characters.';
    }
    return null;
  }

  Future<bool> _isLoginNameAvailable(String loginName) async {
    final result = await _supabase.rpc(
      'is_login_name_available',
      params: {'candidate': loginName},
    );
    return result == true;
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
                          if (_isCreatingAccount) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _loginNameController,
                              enabled: !_isWorking,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              maxLength: 50,
                              validator: _validateLoginName,
                              decoration: const InputDecoration(
                                labelText: 'Login name (optional)',
                                helperText: 'Must be unique if provided.',
                                prefixIcon: Icon(Icons.badge_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
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
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'or',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            onPressed: _isWorking ? null : _signInWithGoogle,
                            icon: const Icon(Icons.g_mobiledata, size: 28),
                            // One label for both modes: with Google there is no
                            // separate sign-up — a first sign-in creates the
                            // account, and an existing address signs into it.
                            label: const Text('Continue with Google'),
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
