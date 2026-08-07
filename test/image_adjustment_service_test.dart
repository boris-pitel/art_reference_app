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
}
