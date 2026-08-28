import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'desktop_oauth_listener.dart';

/// Signing in through an identity provider, by whichever route the platform
/// allows.
///
/// Google and Apple differ only in which provider is named and which marker is
/// left behind for the web redirect, so the mechanics live here once. Both
/// land on the same account: ownership is derived from the email address
/// (`uuidV5` of `art-reference-user:<email>`), so whichever door somebody comes
/// through, they arrive at the library they already had.
class OAuthSignInService {
  const OAuthSignInService({
    required this.provider,
    required this.name,
    required this.startedAtKey,
  });

  final OAuthProvider provider;

  /// What the activity log calls it.
  final String name;

  /// Where the "a web sign-in started" marker is kept. Per provider, so two
  /// attempts in a row cannot be attributed to the wrong one.
  final String startedAtKey;

  /// Where Supabase sends the browser once the provider has authenticated.
  ///
  /// Web returns to the app's own origin. Mobile returns through a custom
  /// scheme the app registers. Desktop has neither, so it returns to a
  /// loopback address the app listens on for the duration of the sign-in.
  static const mobileRedirect = 'com.painterreference.app://login-callback';
  static const desktopRedirect = 'http://localhost:8765';

  /// How long a started sign-in stays claimable.
  ///
  /// The round trip takes seconds. Anything older was abandoned — the user
  /// closed the tab, or went back — and attaching it to whatever session
  /// happens to exist later would put a login in the log that nobody
  /// performed, which is worse than no entry at all when something is being
  /// diagnosed.
  static const claimWindow = Duration(minutes: 5);

  /// Records that a web sign-in started, so the redirect that follows can be
  /// attributed to this provider rather than looking like an ordinary session.
  Future<void> markWebSignInPending() async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setInt(
      startedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// True once, for a sign-in that started recently enough to be this one.
  ///
  /// The marker is cleared whether or not it is claimed, so a stale one cannot
  /// linger and attach itself to some later session.
  Future<bool> consumeWebSignInPending() async {
    final preferences = await SharedPreferences.getInstance();

    final startedAt = preferences.getInt(startedAtKey);
    if (startedAt == null) return false;

    await preferences.remove(startedAtKey);

    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(startedAt),
    );

    return !age.isNegative && age <= claimWindow;
  }

  Future<void> signIn() async {
    final auth = Supabase.instance.client.auth;

    if (kIsWeb) {
      // The page navigates away here and nothing after this line runs, so the
      // sign-in cannot be logged from this side. A marker is left instead, and
      // the auth listener records the login once the redirect lands.
      await markWebSignInPending();

      await auth.signInWithOAuth(provider);
      return;
    }

    if (isDesktop) {
      await _signInOnDesktop(auth);
      return;
    }

    await auth.signInWithOAuth(
      provider,
      redirectTo: mobileRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  /// Desktop has no deep links, so the app briefly becomes a web server.
  ///
  /// Supabase's PKCE flow returns its authorisation code as a query parameter,
  /// which a local server can read — an implicit-flow token would arrive in the
  /// URL fragment, which never reaches the server at all.
  Future<void> _signInOnDesktop(GoTrueClient auth) async {
    final listener = DesktopOAuthListener(port: 8765);

    try {
      final codeArrives = listener.start();

      await auth.signInWithOAuth(
        provider,
        redirectTo: desktopRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      final code = await codeArrives;
      if (code == null) return;

      await auth.exchangeCodeForSession(code);
    } finally {
      await listener.stop();
    }
  }

  static bool get isDesktop {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }
}
