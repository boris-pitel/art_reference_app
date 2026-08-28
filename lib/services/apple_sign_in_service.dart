import 'package:supabase_flutter/supabase_flutter.dart';

import 'oauth_sign_in_service.dart';

/// Signs in through Apple.
///
/// Offered because Apple requires it: an app that lets people sign in with a
/// third-party service must also offer a way that keeps the address private,
/// and email-and-password does not, since the address is real and visible.
/// Apple's relay addresses do.
///
/// A relay address is a real, deliverable address, so it derives an owner id
/// exactly like any other and the library works normally. What it will not do
/// is match an account somebody already made with their own address — signing
/// in with Apple and choosing to hide the address creates a separate library
/// from the one they had. That is inherent to hiding it, not something the
/// app can reconcile, and it is why the sign-in offers no reassurance it
/// cannot keep.
class AppleSignInService {
  const AppleSignInService._();

  static const _oauth = OAuthSignInService(
    provider: OAuthProvider.apple,
    name: 'apple',
    startedAtKey: 'apple_sign_in_started_at',
  );

  static Future<void> signIn() => _oauth.signIn();

  static Future<void> markWebSignInPending() => _oauth.markWebSignInPending();

  static Future<bool> consumeWebSignInPending() =>
      _oauth.consumeWebSignInPending();
}
