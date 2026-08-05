import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:painter_reference_admin/main.dart';

void main() {
  testWidgets('configuration error never exposes a secret input', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ConfigurationErrorApp(
        error: 'Administrative credentials are missing.',
      ),
    );

    expect(find.text('Painter Reference Admin'), findsOneWidget);
    expect(find.textContaining('credentials are missing'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
