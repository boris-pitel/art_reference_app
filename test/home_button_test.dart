import 'package:art_reference_app/widgets/home_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home button returns to the existing Categories screen', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Categories home')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const _SecondaryScreen()),
    );
    await tester.pumpAndSettle();

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
