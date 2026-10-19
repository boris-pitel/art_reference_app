import 'package:art_reference_app/screens/unison_match_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test('matching is available on Windows, iOS and Android', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        unisonMatchingAvailable,
        platform == TargetPlatform.windows ||
            platform == TargetPlatform.iOS ||
            platform == TargetPlatform.android,
      );
    }
  });
}
