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
            onEditWithAi: () {},
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
}
