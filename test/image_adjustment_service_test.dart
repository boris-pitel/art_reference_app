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
