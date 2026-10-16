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
 if(s==='input.qty:not(:disabled)'||s==='a.buy-sku')return buy?{}:null;
 return null;
}};}
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
        rows.map(
          (row) => classifyDakotaStock(Map<String, dynamic>.from(row as Map)),
        ),
        [DakotaStock.inStock, DakotaStock.outOfStock, DakotaStock.discontinued],
      );
      expect(jsonDecode(lines[1]), isEmpty);
    },
  );
}
