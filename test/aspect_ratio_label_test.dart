import 'package:art_reference_app/utils/aspect_ratio_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('describeAspectRatio', () {
    test('reduces a tidy photograph to whole numbers', () {
      // A phone camera at 12MP.
      expect(describeAspectRatio(4032, 3024), startsWith('4 : 3'));
      expect(describeAspectRatio(6000, 4000), startsWith('3 : 2'));
      expect(describeAspectRatio(1920, 1080), startsWith('16 : 9'));
      expect(describeAspectRatio(2000, 2000), startsWith('1 : 1'));
    });

    test('keeps portrait and landscape distinct', () {
      expect(describeAspectRatio(3024, 4032), startsWith('3 : 4'));
      expect(describeAspectRatio(1080, 1920), startsWith('9 : 16'));
    });

    test('names the nearest familiar proportion for an untidy crop', () {
      // A hand-dragged crop almost never reduces to small whole numbers, and
      // 2711 : 1807 answers nothing an artist asked.
      final described = describeAspectRatio(2711, 1807);

      expect(described, startsWith('≈ 3 : 2'));
      expect(described, contains('1.50'));
    });

    test('does not force a ratio that is genuinely unusual', () {
      // Far enough from anything familiar that claiming a match would be a
      // lie; the decimal is the honest answer.
      final described = describeAspectRatio(1000, 731);

      expect(described, isNot(contains(':  (')));
      expect(described, contains('1.37'));
      expect(described, isNot(contains('≈')));
    });

    test('keeps 3 : 2 and 7 : 5 apart', () {
      // Only 1.7% apart, so a loose tolerance would collapse them into one.
      expect(describeAspectRatio(3000, 2000), startsWith('3 : 2'));
      expect(describeAspectRatio(2100, 1500), startsWith('7 : 5'));
    });

    test('always carries the decimal, which is what compares two images', () {
      expect(describeAspectRatio(4032, 3024), contains('1.33 : 1'));
      expect(describeAspectRatio(3024, 4032), contains('1 : 1.33'));
    });

    test('refuses to invent a ratio from impossible dimensions', () {
      expect(describeAspectRatio(0, 100), 'unknown');
      expect(describeAspectRatio(100, 0), 'unknown');
      expect(describeAspectRatio(-4, 3), 'unknown');
    });
  });
}
