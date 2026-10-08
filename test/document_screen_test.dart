import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:art_reference_app/models/reference_document.dart';
import 'package:art_reference_app/screens/document_screen.dart';
import 'package:art_reference_app/services/document_service.dart';

class _DocumentService extends DocumentService {
  _DocumentService({this.error})
    : super(
        SupabaseClient(
          'https://example.test',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final Object? error;
  @override
  bool get offline => true;
  @override
  Future<Uint8List> bytes(ReferenceDocument doc) async {
    if (error != null) throw error!;
    return Uint8List.fromList('A study of light and shadow'.codeUnits);
  }
}

ReferenceDocument document(String type) => ReferenceDocument(
  id: 'doc-1',
  filename: 'study.$type',
  fileType: type,
  storagePath: 'owner/doc-1.$type',
  sizeBytes: 26,
  dateAdded: DateTime(2026),
  title: 'Study',
);
void main() {
  testWidgets('text document opens readably offline and offers save', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentScreen(
          document: document('txt'),
          service: _DocumentService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A study of light and shadow'), findsOneWidget);
    expect(find.byTooltip('Save document'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Word document offers external opening without image tools', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentScreen(
          document: document('docx'),
          service: _DocumentService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open in default app'), findsOneWidget);
    expect(find.text('study.docx'), findsOneWidget);
    expect(find.text('Crop'), findsNothing);
  });
  testWidgets('uncached offline document explains recovery', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DocumentScreen(
          document: document('pdf'),
          service: _DocumentService(
            error: StateError(
              'Open this document online once to keep a copy on this device.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Open this document online once'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });
}
