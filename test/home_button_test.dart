import 'package:art_reference_app/widgets/home_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home button clears the stack and opens Categories', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const _SecondaryScreen(),
        routes: {
          categoriesHomeRoute: (_) =>
              const Scaffold(body: Text('Categories home')),
        },
      ),
    );

    await tester.tap(find.byTooltip('Home — Categories'));
    await tester.pumpAndSettle();

    expect(find.text('Categories home'), findsOneWidget);
    expect(find.text('Secondary screen'), findsNothing);
  });
}

class _SecondaryScreen extends StatelessWidget {
  const _SecondaryScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: const [HomeButton()]),
      body: const Text('Secondary screen'),
    );
  }
}
