import 'dart:typed_data';

import 'package:art_reference_app/screens/image_adjustment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _testImageBytes() {
  final image = img.Image(width: 120, height: 80);
  img.fill(image, color: img.ColorRgb8(80, 110, 140));
  img.drawLine(
    image,
    x1: 0,
    y1: 40,
    x2: 119,
    y2: 40,
    color: img.ColorRgb8(245, 245, 245),
    thickness: 3,
  );
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  testWidgets('Crop & Straighten exposes adjustment controls', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ImageAdjustmentScreen(imageBytes: _testImageBytes())),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.text('Crop & Straighten'), findsOneWidget);
    expect(find.text('Straighten angle'), findsOneWidget);
    expect(find.text('Auto straighten'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Width'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Height'), findsOneWidget);
  });
}
