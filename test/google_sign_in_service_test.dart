import 'package:art_reference_app/services/google_sign_in_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('GoogleSignInService web sign-in marker', () {
    test('a sign-in just started is claimable', () async {
      await GoogleSignInService.markWebSignInPending();

      expect(await GoogleSignInService.consumeWebSignInPending(), isTrue);
    });

    test('claiming it once consumes it', () async {
      await GoogleSignInService.markWebSignInPending();

      await GoogleSignInService.consumeWebSignInPending();

      // A second read must not report another sign-in: the page can be
      // reloaded, and restoring a session is not a fresh login.
      expect(await GoogleSignInService.consumeWebSignInPending(), isFalse);
    });

    test('no marker means no sign-in', () async {
      expect(await GoogleSignInService.consumeWebSignInPending(), isFalse);
    });

    test('an abandoned sign-in is not claimed later', () async {
      // Older than the claim window: the user started a sign-in, went away,
      // and came back much later. Attributing that to whatever session exists
      // now would log a login nobody performed.
      SharedPreferences.setMockInitialValues({
        'flutter.google_sign_in_started_at': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      });

      expect(await GoogleSignInService.consumeWebSignInPending(), isFalse);
    });

    test('a stale marker is cleared, not left to be claimed again', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.google_sign_in_started_at': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      });

      await GoogleSignInService.consumeWebSignInPending();

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('google_sign_in_started_at'), isNull);
    });

    test('a marker from the previous build is discarded', () async {
      // The earlier version stored a bool under a different key and never
      // consumed it, so one could still be sitting in storage.
      SharedPreferences.setMockInitialValues({
        'flutter.google_sign_in_pending': true,
      });

      expect(await GoogleSignInService.consumeWebSignInPending(), isFalse);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('google_sign_in_pending'), isNull);
    });

    test('a clock moved backwards does not claim a future marker', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.google_sign_in_started_at': DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      });

      expect(await GoogleSignInService.consumeWebSignInPending(), isFalse);
    });
  });
}
