import 'dart:async';
import 'dart:typed_data';
import 'package:art_reference_app/widgets/unison_photo_search_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'captured bytes open matching once and cancellation opens nothing',
    (tester) async {
      final captured = Completer<Uint8List?>();
      var captures = 0, opened = 0;
      Uint8List? received;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnisonPhotoSearchButton(
              capture: () {
                captures++;
                return captured.future;
              },
              openMatches: (bytes) async {
                opened++;
                received = bytes;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Search by camera'));
      await tester.pump();
      await tester.tap(find.text('Opening photo…'));
      expect(captures, 1);
      final bytes = Uint8List.fromList([1, 2, 3]);
      captured.complete(bytes);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(received, same(bytes));
      expect(find.text('Search by camera'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnisonPhotoSearchButton(
              capture: () async => null,
              openMatches: (_) async {
                opened++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Search by camera'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    },
  );

  testWidgets(
    'capture errors recover and leaving during capture does not navigate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnisonPhotoSearchButton(
              capture: () async => throw StateError('Camera permission denied'),
              openMatches: (_) async => fail('Should not open matching'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Search by camera'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Camera permission denied'), findsOneWidget);
      expect(find.text('Search by camera'), findsOneWidget);
      final pending = Completer<Uint8List?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnisonPhotoSearchButton(
              capture: () => pending.future,
              openMatches: (_) async =>
                  fail('Disposed capture must not navigate'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Search by camera'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete(Uint8List.fromList([1]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
