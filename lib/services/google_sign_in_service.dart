import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'oauth_sign_in_service.dart';

/// Signs in through Google.
///
/// The account is matched by email, and library ownership is derived from the
/// email too (`uuidV5` of `art-reference-user:<email>`), so signing in with
/// Google using an address that already has a password account lands on the
/// same library. Google is a second door to one account, not a second account.
///
/// The mechanics live in [OAuthSignInService], which Apple shares.
class GoogleSignInService {
  const GoogleSignInService._();

  static const _oauth = OAuthSignInService(
    provider: OAuthProvider.google,
    name: 'google',
    startedAtKey: 'google_sign_in_started_at',
  );

  /// Superseded by the key above, which records when rather than whether.
  /// Cleared on sight so a marker left by an older build cannot be read as a
  /// sign-in that never happened.
  static const _legacyPendingKey = 'google_sign_in_pending';

  static Future<void> signIn() => _oauth.signIn();

  static Future<void> markWebSignInPending() => _oauth.markWebSignInPending();

  static Future<bool> consumeWebSignInPending() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_legacyPendingKey);

    return _oauth.consumeWebSignInPending();
  }
}
