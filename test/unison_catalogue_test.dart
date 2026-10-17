import 'package:art_reference_app/services/dakota_stock.dart';
import 'package:art_reference_app/services/unison_catalogue.dart';
import 'package:art_reference_app/widgets/unison_catalogue_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rows = [
    {
      'code': 'BE14',
      'retailer_sku': 'UNSBE14',
      'display_name': 'Unison Brown Earth 14',
      'approximate_name': 'Warm beige',
    },
    {
      'code': 'GREY14',
      'retailer_sku': 'UNSGREY14',
      'display_name': 'Unison Grey 14',
    },
  ];
  test('search matches code, retailer SKU, names, and every search word', () {
    for (final query in [
      'be14',
      'UNSBE14',
      'brown earth',
      'BROWN EARTH',
      'bRoWn EaRtH',
      'Be 14',
      'warm beige',
    ]) {
      expect(searchUnisonCatalogue(rows, query).single['code'], 'BE14');
    }
    expect(searchUnisonCatalogue(rows, 'no such pastel'), isEmpty);
    expect(searchUnisonCatalogue(rows, 'Brown Grey'), isEmpty);
    expect(searchUnisonCatalogue(rows, '   ').length, 2);
    final sorted = [
      {'code': 'A10'},
      {'code': 'BE1'},
      {'code': 'A2'},
    ]..sort(compareUnisonCodes);
    expect(sorted.map((row) => row['code']), ['A2', 'A10', 'BE1']);
  });
  testWidgets(
    'no-match search clears results; clear search restores rows and cart controls',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? added;
      int? changed;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnisonCatalogueList(
              rows: rows,
              offers: const {
                'UNSBE14': DakotaOffer(
                  stock: DakotaStock.outOfStock,
                  expected: 'Expected approx 9/18',
                  unitCents: 595,
                ),
              },
              quantities: const {'UNSGREY14': 2},
              onAdd: (row) => added = row['code'] as String,
              onQuantity: (_, qty) => changed = qty,
            ),
          ),
        ),
      );
      expect(find.textContaining('\$5.95 per stick'), findsOneWidget);
      expect(find.text('Out of stock · Expected approx 9/18'), findsOneWidget);
      await tester.tap(find.text('Add'));
      expect(added, 'BE14');
      await tester.tap(find.byTooltip('Increase GREY14'));
      expect(changed, 3);
      await tester.enterText(find.byType(TextField), 'does not exist');
      await tester.pump();
      expect(find.text('No pastels match your search.'), findsOneWidget);
      expect(find.text('Add'), findsNothing);
      expect(find.textContaining('In cart'), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('✓ In cart · 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
