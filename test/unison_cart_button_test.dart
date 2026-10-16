import 'package:art_reference_app/services/unison_cart.dart';
import 'package:art_reference_app/widgets/unison_cart_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'cart quantity updates after add, change, remove and account switch',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const swatch = {
        'retailer_sku': 'UNSBE14',
        'code': 'BE14',
        'display_name': 'Brown Earth 14',
      };
      final cart = UnisonCart('one');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [UnisonCartButton(userId: 'one', onPressed: () {})],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      await cart.add(swatch);
      await cart.add(swatch);
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await cart.quantity('UNSBE14', 5);
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [UnisonCartButton(userId: 'two', onPressed: () {})],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
    await cart.clear();
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
