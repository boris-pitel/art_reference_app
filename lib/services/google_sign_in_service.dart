import 'package:flutter/foundation.dart';
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

  static Future<void> signIn() async {
    final auth = Supabase.instance.client.auth;

    if (kIsWeb) {
      // Navigates away and returns to the app; nothing after this runs.
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
