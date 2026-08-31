import 'dart:async';
import 'dart:typed_data';

import 'package:art_reference_app/screens/image_adjustment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    expect(find.text('Aspect ratio'), findsOneWidget);

    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    final presetValues = tester
        .widgetList<DropdownMenuItem<String>>(
          find.byType(DropdownMenuItem<String>, skipOffstage: false),
        )
        .map((item) => item.value);
    expect(presetValues, contains('a4-p'));
    expect(presetValues, contains('a0-p'));
    expect(presetValues, contains('b5-l'));
    expect(presetValues, contains('letter-l'));
    expect(presetValues, contains('tabloid-p'));
    dropdown.onChanged?.call('Custom');
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Width'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Height'), findsOneWidget);
  });

  testWidgets('Edit with AI is part of the control panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageAdjustmentScreen(
            imageBytes: _testImageBytes(),
            embedded: true,
            onEditWithAi: (_) {},
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Edit with AI'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('Save reports processing before image work starts', (
    tester,
  ) async {
    final controller = ImageAdjustmentController();
    final processingStates = <bool>[];
    final imageWork = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageAdjustmentScreen(
            imageBytes: _testImageBytes(),
            embedded: true,
            controller: controller,
            onProcessingChanged: processingStates.add,
            onDone: (_) {},
            imageProcessor:
                ({
                  required bytes,
                  required angle,
                  required crop,
                  monochrome = false,
                  gridDivisions = 0,
                }) => imageWork.future,
          ),
        ),
      ),
    );

    final applying = controller.apply();
    expect(processingStates, [isTrue]);

    await tester.pump();
    imageWork.complete(_testImageBytes());
    await applying;
    expect(processingStates, [isTrue, isFalse]);
  });

  testWidgets('1:1 crop on a 3:4 image produces a square pixel region', (
    tester,
  ) async {
    final portrait = img.Image(width: 90, height: 120);
    img.fill(portrait, color: img.ColorRgb8(80, 110, 140));
    final controller = ImageAdjustmentController();
    Rect? appliedCrop;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageAdjustmentScreen(
            imageBytes: Uint8List.fromList(img.encodeJpg(portrait)),
            embedded: true,
            controller: controller,
            onDone: (_) {},
            imageProcessor:
                ({
                  required bytes,
                  required angle,
                  required crop,
                  monochrome = false,
                  gridDivisions = 0,
                }) async {
                  appliedCrop = crop;
                  return bytes;
                },
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    dropdown.onChanged?.call('1:1');
    await tester.pump();
    final applying = controller.apply();
    await tester.pump();
    await applying;

    expect(appliedCrop, isNotNull);
    expect(appliedCrop!.width * 90, closeTo(appliedCrop!.height * 120, 0.01));
    expect(appliedCrop!.width, closeTo(1, 0.001));
    expect(appliedCrop!.height, closeTo(0.75, 0.001));
  });
}
