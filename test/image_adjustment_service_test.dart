import 'dart:typed_data';
import 'dart:ui';

import 'package:art_reference_app/services/image_adjustment_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('applies normalized crop and emits a decodable image', () async {
    final source = img.Image(width: 100, height: 80);
    img.fill(source, color: img.ColorRgb8(120, 80, 40));
    final bytes = Uint8List.fromList(img.encodePng(source));

    final result = await ImageAdjustmentService.apply(
      bytes: bytes,
      angle: 0,
      crop: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
    );
    final decoded = img.decodeImage(result);

    expect(decoded, isNotNull);
    expect(decoded!.width, 50);
    expect(decoded.height, 40);
  });

  test(
    'keeps a one-pixel crop when rounding reaches the bottom-right edge',
    () async {
      final source = img.Image(width: 10, height: 10);
      img.fill(source, color: img.ColorRgb8(120, 80, 40));

      final result = await ImageAdjustmentService.apply(
        bytes: Uint8List.fromList(img.encodePng(source)),
        angle: 0,
        crop: const Rect.fromLTWH(0.96, 0.96, 0.04, 0.04),
      );
      final decoded = img.decodeImage(result);

      expect(decoded, isNotNull);
      expect(decoded!.width, 1);
      expect(decoded.height, 1);
    },
  );

  test(
    'accepts an origin exactly on the normalized bottom-right boundary',
    () async {
      final source = img.Image(width: 3, height: 2);

      final result = await ImageAdjustmentService.apply(
        bytes: Uint8List.fromList(img.encodePng(source)),
        angle: 0,
        crop: const Rect.fromLTWH(1, 1, 0.01, 0.01),
      );
      final decoded = img.decodeImage(result);

      expect(decoded, isNotNull);
      expect(decoded!.width, 1);
      expect(decoded.height, 1);
    },
  );

  test('detects an already-horizontal reference line as straight', () async {
    final source = img.Image(width: 160, height: 100);
    img.fill(source, color: img.ColorRgb8(40, 40, 40));
    for (final y in [25, 50, 75]) {
      img.drawLine(
        source,
        x1: 0,
        y1: y,
        x2: 159,
        y2: y,
        color: img.ColorRgb8(240, 240, 240),
        thickness: 3,
      );
    }

    final angle = await ImageAdjustmentService.detectStraightenAngle(
      Uint8List.fromList(img.encodePng(source)),
    );

    expect(angle, closeTo(0, 0.35));
  });

  test('leaves colour alone unless monochrome is asked for', () async {
    final source = img.Image(width: 8, height: 8);
    img.fill(source, color: img.ColorRgb8(200, 30, 30));

    final result = await ImageAdjustmentService.apply(
      bytes: Uint8List.fromList(img.encodePng(source)),
      angle: 0,
      crop: const Rect.fromLTWH(0, 0, 1, 1),
    );
    final pixel = img.decodeImage(result)!.getPixel(4, 4);

    expect(pixel.r, greaterThan(pixel.g + 40));
  });

  test('monochrome weights luminance rather than averaging channels', () async {
    // A saturated red and a mid green average to nearly the same grey, so an
    // averaging conversion would render them identically - which is exactly the
    // mistake an artist switches to monochrome to catch.
    Future<num> greyOf(img.ColorRgb8 colour) async {
      final source = img.Image(width: 8, height: 8);
      img.fill(source, color: colour);

      final result = await ImageAdjustmentService.apply(
        bytes: Uint8List.fromList(img.encodePng(source)),
        angle: 0,
        crop: const Rect.fromLTWH(0, 0, 1, 1),
        monochrome: true,
      );
      final pixel = img.decodeImage(result)!.getPixel(4, 4);

      expect(pixel.r, closeTo(pixel.g.toDouble(), 2));
      expect(pixel.g, closeTo(pixel.b.toDouble(), 2));

      return pixel.r;
    }

    final red = await greyOf(img.ColorRgb8(255, 0, 0));
    final green = await greyOf(img.ColorRgb8(0, 255, 0));

    expect(red, closeTo(255 * luminanceRed, 3));
    expect(green, closeTo(255 * luminanceGreen, 3));
    expect(green, greaterThan(red + 100));
  });

  test('leaves the picture unmarked unless a grid is asked for', () async {
    final source = img.Image(width: 60, height: 60);
    img.fill(source, color: img.ColorRgb8(120, 120, 120));

    final result = await ImageAdjustmentService.apply(
      bytes: Uint8List.fromList(img.encodePng(source)),
      angle: 0,
      crop: const Rect.fromLTWH(0, 0, 1, 1),
    );
    final decoded = img.decodeImage(result)!;

    for (var x = 0; x < decoded.width; x++) {
      expect(decoded.getPixel(x, 30).r, closeTo(120, 12));
    }
  });

  test('draws the grid into the saved image at the division lines', () async {
    // The grid method for transferring a drawing: the lines are the point, so
    // they have to survive the save rather than being a viewing aid.
    final source = img.Image(width: 300, height: 300);
    img.fill(source, color: img.ColorRgb8(120, 120, 120));

    final result = await ImageAdjustmentService.apply(
      bytes: Uint8List.fromList(img.encodePng(source)),
      angle: 0,
      crop: const Rect.fromLTWH(0, 0, 1, 1),
      gridDivisions: 3,
    );
    final decoded = img.decodeImage(result)!;

    // Thirds of 300 are at 100 and 200, and nowhere else.
    for (final x in const [100, 200]) {
      expect(decoded.getPixel(x, 150).r, isNot(closeTo(120, 20)));
    }
    for (final y in const [100, 200]) {
      expect(decoded.getPixel(150, y).r, isNot(closeTo(120, 20)));
    }

    expect(decoded.getPixel(50, 50).r, closeTo(120, 12));
    expect(decoded.getPixel(150, 150).r, closeTo(120, 12));
  });

  test('divides the crop, not the original', () async {
    // The crop is what gets saved, so a third has to be a third of that. Using
    // the original would put the lines at the wrong places in the output.
    final source = img.Image(width: 400, height: 400);
    img.fill(source, color: img.ColorRgb8(120, 120, 120));

    final result = await ImageAdjustmentService.apply(
      bytes: Uint8List.fromList(img.encodePng(source)),
      angle: 0,
      crop: const Rect.fromLTWH(0.5, 0.5, 0.5, 0.5),
      gridDivisions: 2,
    );
    final decoded = img.decodeImage(result)!;

    expect(decoded.width, 200);
    expect(decoded.getPixel(100, 100).r, isNot(closeTo(120, 20)));
    expect(decoded.getPixel(30, 30).r, closeTo(120, 12));
  });

  test('scales line weight to the size of the picture', () async {
    Future<int> markedColumns(int size) async {
      final source = img.Image(width: size, height: size);
      img.fill(source, color: img.ColorRgb8(120, 120, 120));

      final result = await ImageAdjustmentService.apply(
        bytes: Uint8List.fromList(img.encodePng(source)),
        angle: 0,
        crop: const Rect.fromLTWH(0, 0, 1, 1),
        gridDivisions: 2,
      );
      final decoded = img.decodeImage(result)!;
      final middle = decoded.height ~/ 4;

      var marked = 0;
      for (var x = 0; x < decoded.width; x++) {
        if ((decoded.getPixel(x, middle).r - 120).abs() > 20) marked++;
      }
      return marked;
    }

    // A line thin enough to be right on a small image is invisible on a large
    // one, so the weight has to grow with the picture.
    expect(await markedColumns(2400), greaterThan(await markedColumns(400)));
  });

  test('monochrome applies to the cropped region, not the discarded one',
      () async {
    final source = img.Image(width: 20, height: 20);
    img.fill(source, color: img.ColorRgb8(10, 200, 60));

    final result = await ImageAdjustmentService.apply(
      bytes: Uint8List.fromList(img.encodePng(source)),
      angle: 0,
      crop: const Rect.fromLTWH(0.5, 0.5, 0.5, 0.5),
      monochrome: true,
    );
    final decoded = img.decodeImage(result)!;

    expect(decoded.width, 10);
    expect(decoded.height, 10);

    final pixel = decoded.getPixel(5, 5);
    expect(pixel.r, closeTo(pixel.g.toDouble(), 2));
    expect(pixel.g, closeTo(pixel.b.toDouble(), 2));
  });
}
