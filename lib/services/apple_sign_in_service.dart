import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'oauth_sign_in_service.dart';

/// Signs in through Apple.
///
/// Offered because Apple requires it: an app that lets people sign in with a
/// third-party service must also offer a way that keeps the address private,
/// and email-and-password does not, since the address is real and visible.
/// Apple's relay addresses do.
///
/// Two routes, and the difference matters.
///
/// On an iPhone this authenticates on the device, against the app's own bundle
/// id and the Sign in with Apple entitlement. Nothing about it touches the
/// Services ID or a return URL. That is deliberate: the web configuration is
/// refused with invalid_client despite every setting in the developer portal
/// reading as correct, and this route does not pass through the part that is
/// broken. It is also the better experience — Face ID rather than typing an
/// Apple Account password into a browser.
///
/// Everywhere else falls back to the same web flow Google uses. That path is
/// currently the broken one; it is kept because it costs nothing, it is where
/// a fix will land if the portal ever starts behaving, and an iPhone is where
/// Apple's requirement is actually judged.
///
/// A relay address is a real, deliverable address, so it derives an owner id
/// exactly like any other and the library works normally. What it will not do
/// is match an account somebody already made with their own address — hiding
/// the address means a separate library. That is inherent to hiding it, not
/// something the app can reconcile.
class AppleSignInService {
  const AppleSignInService._();

  static const _oauth = OAuthSignInService(
    provider: OAuthProvider.apple,
    name: 'apple',
    startedAtKey: 'apple_sign_in_started_at',
  );

  /// Whether the on-device flow is available here.
  static bool get _isNative {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static Future<void> signIn() async {
    if (_isNative) {
      await _signInNatively();
      return;
    }

    await _oauth.signIn();
  }

  /// The on-device flow.
  ///
  /// Apple returns an identity token which Supabase verifies itself, so no
  /// browser round trip and no redirect are involved. The nonce is what ties
  /// the two together: a random value is hashed and handed to Apple, Apple
  /// embeds the hash in the token it signs, and Supabase is given the original
  /// to check against it. Without that, a token captured elsewhere could be
  /// replayed here.
  static Future<void> _signInNatively() async {
    final rawNonce = _randomNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      // Backing out of the sheet is a decision, not a failure. Letting it
      // through would put "Sign-in failed" on screen for somebody who simply
      // changed their mind.
      if (error.code == AuthorizationErrorCode.canceled) return;

      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Apple did not return an identity token.');
    }

    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
  }

  static String _randomNonce([int length = 32]) {
    const characters =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final random = Random.secure();

    return List.generate(
      length,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  static Future<void> markWebSignInPending() => _oauth.markWebSignInPending();

  static Future<bool> consumeWebSignInPending() =>
      _oauth.consumeWebSignInPending();
}
