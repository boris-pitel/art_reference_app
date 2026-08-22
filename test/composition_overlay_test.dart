import 'dart:ui';

import 'package:art_reference_app/widgets/composition_overlay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompositionGrid', () {
    test('names cells, not lines', () {
      // Thirds is the familiar rule-of-thirds grid: three cells a side, which
      // is two lines each way. Reading these as line counts would draw every
      // grid one division off.
      expect(CompositionGrid.halves.divisions, 2);
      expect(CompositionGrid.thirds.divisions, 3);
      expect(CompositionGrid.quarters.divisions, 4);
    });

    test('none draws nothing', () {
      expect(CompositionGrid.none.divisions, lessThan(2));
    });
  });

  group('containedImageRect', () {
    test('letterboxes a wide picture inside a square viewport', () {
      final rect = containedImageRect(
        const Size(400, 400),
        const Size(200, 100),
      );

      expect(rect.width, 400);
      expect(rect.height, 200);
      expect(rect.top, 100);
      expect(rect.left, 0);
    });

    test('pillarboxes a tall picture inside a wide viewport', () {
      final rect = containedImageRect(
        const Size(400, 200),
        const Size(100, 200),
      );

      expect(rect.width, 100);
      expect(rect.height, 200);
      expect(rect.left, 150);
      expect(rect.top, 0);
    });

    test('fills exactly when the proportions already match', () {
      final rect = containedImageRect(
        const Size(600, 400),
        const Size(300, 200),
      );

      expect(rect, const Rect.fromLTWH(0, 0, 600, 400));
    });

    test('keeps the picture inside the viewport', () {
      // The grid is drawn over this rectangle, so anything spilling past the
      // viewport would put lines outside the image.
      for (final image in const [
        Size(4000, 3000),
        Size(17, 900),
        Size(1, 1),
      ]) {
        final rect = containedImageRect(const Size(320, 240), image);

        expect(rect.left, greaterThanOrEqualTo(-0.001));
        expect(rect.top, greaterThanOrEqualTo(-0.001));
        expect(rect.right, lessThanOrEqualTo(320.001));
        expect(rect.bottom, lessThanOrEqualTo(240.001));
      }
    });

    test('falls back to the whole box for an unmeasurable image', () {
      expect(
        containedImageRect(const Size(300, 200), Size.zero),
        const Rect.fromLTWH(0, 0, 300, 200),
      );
    });
  });
}
