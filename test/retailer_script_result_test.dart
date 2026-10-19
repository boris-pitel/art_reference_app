import 'dart:convert';
import 'package:art_reference_app/services/retailer_script_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'iPhone and Android return the same stock list and cart transfer map',
    () {
      for (final value in [
        [
          {'sku': 'UNSBE14', 'canBuy': true},
        ],
        {
          'missing': ['UNSGREY17'],
          'submitted': false,
        },
      ]) {
        final payload = jsonEncode(value);
        expect(jsonDecode(retailerScriptResult(payload)), value);
        expect(jsonDecode(retailerScriptResult(jsonEncode(payload))), value);
      }
    },
  );
  test('malformed script replies remain errors instead of empty stock', () {
    expect(
      () => jsonDecode(retailerScriptResult('not JSON')),
      throwsFormatException,
    );
  });
}
