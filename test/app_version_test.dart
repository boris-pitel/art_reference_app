import 'dart:io';

import 'package:art_reference_app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('About version label contains public version and build number', () {
    expect(appVersion, matches(RegExp(r'^\d+\.\d+\.\d+\+\d+$')));
    expect(
      appVersionLabel,
      matches(RegExp(r'^Version \d+\.\d+\.\d+ \(Build \d+\)$')),
    );
  });

  test('displayed version matches the package version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(appVersion, match!.group(1));
  });
}
