import 'package:art_reference_app/services/unison_matching.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sRGB conversion matches D65 reference values', () {
    final white = rgbToLab(255, 255, 255);
    expect(white[0], closeTo(100, .001));
    expect(white[1], closeTo(0, .001));
    expect(white[2], closeTo(0, .001));
    final red = rgbToLab(255, 0, 0);
    expect(red[0], closeTo(53.2408, .001));
    expect(red[1], closeTo(80.0925, .001));
    expect(red[2], closeTo(67.2032, .001));
  });
  test('CIEDE2000 published reference pairs, including hue wrap', () {
    const cases = [
      [
        [50.0, 2.6772, -79.7751],
        [50.0, 0.0, -82.7485],
        2.0425,
      ],
      [
        [50.0, 3.1571, -77.2803],
        [50.0, 0.0, -82.7485],
        2.8615,
      ],
      [
        [50.0, 2.8361, -74.0200],
        [50.0, 0.0, -82.7485],
        3.4412,
      ],
      [
        [50.0, 0.0, 0.0],
        [50.0, -1.0, 2.0],
        2.3669,
      ],
      [
        [50.0, 2.49, -.001],
        [50.0, -2.49, .0011],
        7.2195,
      ],
    ];
    for (final pair in cases) {
      final a = pair[0] as List<double>, b = pair[1] as List<double>;
      expect(deltaE2000(a, b), closeTo(pair[2] as double, .0001));
      expect(deltaE2000(b, a), closeTo(pair[2] as double, .0001));
      expect(deltaE2000(a, a), 0);
    }
  });
}
