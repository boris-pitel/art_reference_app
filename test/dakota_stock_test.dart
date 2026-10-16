import 'dart:convert';
import 'dart:io';
import 'package:art_reference_app/services/dakota_stock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit discontinued and stock messages take priority over Buy', () {
    expect(
      classifyDakotaStock({'note': 'Discontinued', 'canBuy': true}),
      DakotaStock.discontinued,
    );
    expect(
      classifyDakotaStock({'actions': 'NOTIFY ME'}),
      DakotaStock.outOfStock,
    );
    expect(
      classifyDakotaStock({'note': 'Expected approx 9/18'}),
      DakotaStock.outOfStock,
    );
    expect(
      classifyDakotaStock({'note': 'Out of stock', 'canBuy': true}),
      DakotaStock.outOfStock,
    );
    expect(classifyDakotaStock({'canBuy': true}), DakotaStock.inStock);
    expect(classifyDakotaStock({}), DakotaStock.unknown);
    expect(classifyDakotaStock({'actions': 'Reserve'}), DakotaStock.unknown);
  });

  test(
    'DOM reader ignores responsive duplicates and unrelated pages',
    () async {
      final result = await Process.run('node', [
        '-e',
        '''
const location={origin:'https://dakotapastels.com',pathname:'/products/Soft-Unison-Individual'};
function row(sku,note,actions,buy,mobile=false){return {querySelector(s){
 if(s==='.sku-code-inner')return {textContent:sku};
 if(s==='.sku-name')return mobile?null:{innerText:note};
 if(s==='.actions')return {innerText:actions};
 if(s==='.oos-message')return {innerText:buy?'':'Expected approx 9/18'};
 if(s==='input.qty:not(:disabled)'||s==='a.buy-sku')return buy?{}:null;
 return null;
},querySelectorAll(){return [{innerText:'\u00245.95',classList:{contains(){return false}}}]}};}
const document={querySelectorAll(){return [row('UNSBE14','Unison Brown Earth 14','Buy',true),row('UNSGREY14','Expected approx 9/18','Notify Me',false),row('UNSGREY14','','Reserve',false,true),row('UNSA1','Discontinued','',false)]}};
console.log($dakotaStockScript);
location.pathname='/Checkout/Cart';
console.log($dakotaStockScript);
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final lines = (result.stdout as String).trim().split('\n');
      final rows = jsonDecode(lines[0]) as List;
      expect(rows.length, 3);
      expect(
        DakotaOffer.fromRow(
          Map<String, dynamic>.from(rows[0] as Map),
        ).unitCents,
        595,
      );
      expect(
        DakotaOffer.fromRow(
          Map<String, dynamic>.from(rows[1] as Map),
        ).availability,
        'Out of stock · Expected approx 9/18',
      );
      expect(
        rows.map(
          (row) => classifyDakotaStock(Map<String, dynamic>.from(row as Map)),
        ),
        [DakotaStock.inStock, DakotaStock.outOfStock, DakotaStock.discontinued],
      );
      expect(jsonDecode(lines[1]), isEmpty);
    },
  );
  test('USD prices and sale labels preserve cents and unknowns', () {
    expect(parseDakotaPrice('\$5.95'), 595);
    expect(parseDakotaPrice('\$1,234.56'), 123456);
    expect(parseDakotaPrice(''), isNull);
    expect(parseDakotaPrice('Call for price'), isNull);
    expect(parseDakotaPrice('5.95'), isNull);
    final sale = DakotaOffer.fromRow({
      'price': '\$4.50',
      'regularPrice': '\$5.95',
    });
    expect(sale.priceLabel, 'Sale \$4.50 per stick (was \$5.95)');
    final estimate = DakotaCartEstimate(
      [
        {'sku': 'UNSA1', 'quantity': 3},
        {'sku': 'UNSA2', 'quantity': 2},
      ],
      {'UNSA1': sale},
    );
    expect(estimate.knownCents, 1350);
    expect(estimate.unpricedSticks, 2);
    expect(estimate.label, contains('Known-price subtotal'));
    expect(
      DakotaCartEstimate(
        [
          {'sku': 'UNSA1', 'quantity': 3},
        ],
        {'UNSA1': sale},
      ).label,
      'Estimated total: \$13.50 USD',
    );
  });
}
