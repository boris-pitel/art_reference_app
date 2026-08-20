import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'desktop_oauth_listener.dart';

/// Signs in through Google, by whichever route the platform allows.
///
/// The account is matched by email, and library ownership is derived from the
/// email too (`uuidV5` of `art-reference-user:<email>`), so signing in with
/// Google using an address that already has a password account lands on the
/// same library. Google is a second door to one account, not a second account.
class GoogleSignInService {
  const GoogleSignInService._();

  /// Where Supabase sends the browser once Google has authenticated.
  ///
  /// Web returns to the app's own origin. Mobile returns through a custom
  /// scheme the app registers. Desktop has neither, so it returns to a
  /// loopback address that the app listens on for the duration of the sign-in.
  static const _mobileRedirect = 'com.painterreference.app://login-callback';
  static const _desktopRedirect = 'http://localhost:8765';

  static const _startedAtKey = 'google_sign_in_started_at';

  /// Superseded by [_startedAtKey], which records when rather than whether.
  /// Cleared on sight so a marker left by the older build cannot be read as a
  /// sign-in that never happened.
  static const _legacyPendingKey = 'google_sign_in_pending';

  /// How long a started sign-in stays claimable.
  ///
  /// The round trip through Google takes seconds. Anything older was abandoned
  /// — the user closed the tab, or went back — and attaching it to whatever
  /// session happens to exist later would put a login in the log that nobody
  /// performed, which is worse than no entry at all when something is being
  /// diagnosed.
  static const _claimWindow = Duration(minutes: 5);

  /// Records that a web sign-in started, so the redirect that follows can be
  /// attributed to Google rather than looking like an ordinary session.
  static Future<void> markWebSignInPending() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setInt(
      _startedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// True once, for a sign-in that started recently enough to be this one.
  ///
  /// The marker is cleared whether or not it is claimed, so a stale one cannot
  /// linger and attach itself to some later session.
  static Future<bool> consumeWebSignInPending() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.remove(_legacyPendingKey);

    final startedAt = preferences.getInt(_startedAtKey);
    if (startedAt == null) return false;

    await preferences.remove(_startedAtKey);

    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(startedAt),
    );

    return !age.isNegative && age <= _claimWindow;
  }

  static Future<void> signIn() async {
    final auth = Supabase.instance.client.auth;

    if (kIsWeb) {
      // The page navigates away here and nothing after this line runs, so the
      // sign-in cannot be logged from this side. A marker is left instead, and
      // the auth listener records the login once the redirect lands.
      await markWebSignInPending();

      await auth.signInWithOAuth(OAuthProvider.google);
      return;
    }

    if (_isDesktop) {
      await _signInOnDesktop(auth);
      return;
    }

    await auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _mobileRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// Desktop has no deep links, so the app briefly becomes a web server.
  ///
  /// Supabase's PKCE flow returns its authorisation code as a query parameter,
  /// which a local server can read — an implicit-flow token would arrive in the
  /// URL fragment, which never reaches the server at all.
  static Future<void> _signInOnDesktop(GoTrueClient auth) async {
    final listener = DesktopOAuthListener(port: 8765);

    try {
      final codeArrives = listener.start();

      await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _desktopRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      final code = await codeArrives;
      if (code == null) return;

      await auth.exchangeCodeForSession(code);
    } finally {
      await listener.stop();
    }
  }

  static bool get _isDesktop {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }
}
