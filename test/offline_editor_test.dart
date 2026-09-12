import 'dart:convert';
import 'dart:typed_data';

import 'package:art_reference_app/screens/ai_image_edit_screen.dart';
import 'package:art_reference_app/screens/image_adjustment_screen.dart';
import 'package:art_reference_app/services/network_availability.dart';
import 'package:art_reference_app/widgets/offline_editing_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Uint8List pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHZkAAAAASUVORK5CYII=',
);

class FailureEditor extends StatefulWidget {
  const FailureEditor({super.key});
  @override
  State<FailureEditor> createState() => FailureEditorState();
}

class FailureEditorState extends State<FailureEditor>
    with OfflineEditorState<FailureEditor> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: offlineEditorBody(
      TextButton(
        onPressed: () => reportEditorFailure(
          StateError(
            'ClientException: Connection closed before full header was received',
          ),
        ),
        child: const Text('Save'),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConnectivityMonitor.instance.setForTesting(BackendConnectivityState.online);
  });
  tearDown(
    () => ConnectivityMonitor.instance.setForTesting(
      BackendConnectivityState.unknown,
    ),
  );

  testWidgets('failed editor request updates shared offline state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: FailureEditor()));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(ConnectivityMonitor.instance.isOffline, isTrue);
    expect(find.textContaining('Offline — editing'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('AI editor reacts to connection loss and preserves the prompt', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AiImageEditScreen(
          sourceImageId: 'source',
          sourceImageUrl: '',
          sourceImageBytes: pixel,
          parentImageId: 'parent',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    ConnectivityMonitor.instance.setForTesting(
      BackendConnectivityState.noInternet,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline — editing'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my draft',
    );
    ConnectivityMonitor.instance.setForTesting(BackendConnectivityState.online);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep my draft',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('open crop editor blocks controller save after connection loss', (
    tester,
  ) async {
    var saves = 0;
    final controller = ImageAdjustmentController();
    await tester.pumpWidget(
      MaterialApp(
        home: ImageAdjustmentScreen(
          imageBytes: pixel,
          controller: controller,
          onDone: (_) {
            saves++;
          },
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    ConnectivityMonitor.instance.setForTesting(
      BackendConnectivityState.noInternet,
    );
    await tester.pump();
    await controller.apply();
    expect(saves, 0);
    expect(find.textContaining('Offline — editing'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Done'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('outline controls fill an editable prompt and clear it in one tap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: AiImageEditScreen(
      sourceImageId: 'source', sourceImageUrl: 'https://example.com/image.png',
      sourceImageBytes: pixel, parentImageId: 'parent')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Outline'));
    await tester.tap(find.text('Outline'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, contains('thin, clean black lines'));
    await tester.tap(find.text('thin lines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('thick lines').last);
    await tester.pumpAndSettle();
    expect(field.controller!.text, contains('thick, clean black lines'));
    await tester.tap(find.text('Clear prompt'));
    await tester.pump();
    expect(field.controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

}
