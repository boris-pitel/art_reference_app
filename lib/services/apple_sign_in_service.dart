import 'package:supabase_flutter/supabase_flutter.dart';

import 'oauth_sign_in_service.dart';

/// Signs in through Apple.
///
/// Not currently offered anywhere in the app. Apple refuses to authorise this
/// app for Sign in with Apple by either route — invalid_client through the
/// Services ID, ASAuthorizationError 1000 through the on-device entitlement —
/// with every setting in their developer portal reading as correct. Testing
/// Apple's authorize endpoint directly, with this app and Supabase out of the
/// picture, produced the same refusal, so it is their registration rather than
/// this code.
///
/// Kept because the Supabase side is configured and working, and the button
/// can go back on the login screen in one line the day Apple starts answering.
/// The native on-device flow lived here too and is in the history if it is
/// wanted again; it needs the sign_in_with_apple package and an entitlement,
/// both removed rather than left declaring a capability the app does not use.
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
