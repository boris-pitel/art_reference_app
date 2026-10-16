import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UnisonCart {
  UnisonCart(this.userId);
  final String userId;
  static Future<void> _writes = Future.value();
  static final changes = ValueNotifier<int>(0);
  String get _key => 'unison_cart_v1:$userId';
  Future<List<Map<String, dynamic>>> load() async {
    await _writes;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  Future<void> _change(void Function(List<Map<String, dynamic>>) change) {
    final operation = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final rows = raw == null
          ? <Map<String, dynamic>>[]
          : (jsonDecode(raw) as List)
                .map((r) => Map<String, dynamic>.from(r as Map))
                .toList();
      change(rows);
      if (!await prefs.setString(_key, jsonEncode(rows))) {
        throw StateError('Unable to save shopping cart.');
      }
      changes.value++;
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> add(Map<String, dynamic> swatch) {
    final sku = swatch['retailer_sku'];
    if (sku is! String || !RegExp(r'^UNS[A-Z]+[0-9]+$').hasMatch(sku)) {
      throw StateError('Dakota product code is missing.');
    }
    return _change((rows) {
      final index = rows.indexWhere((r) => r['sku'] == sku);
      if (index >= 0) {
        final qty = (rows[index]['quantity'] as int) + 1;
        if (qty > 99) throw StateError('Maximum quantity is 99 per colour.');
        rows[index]['quantity'] = qty;
      } else {
        rows.add({
          'sku': sku,
          'code': swatch['code'],
          'name': swatch['display_name'],
          'swatch_path': swatch['swatch_path'],
          'quantity': 1,
        });
      }
    });
  }

  Future<void> quantity(String sku, int quantity) {
    if (quantity < 0 || quantity > 99) throw RangeError.range(quantity, 0, 99);
    return _change((rows) {
      if (quantity == 0) {
        rows.removeWhere((r) => r['sku'] == sku);
      } else {
        for (final row in rows) {
          if (row['sku'] == sku) row['quantity'] = quantity;
        }
      }
    });
  }
}

/// Acts only on Dakota's public product rows, and never on checkout controls.
String dakotaCartScript(
  List<Map<String, dynamic>> items, {
  bool submit = false,
}) =>
    '''
(() => {
 if(location.origin !== 'https://dakotapastels.com' || location.pathname !== '/products/Soft-Unison-Individual') throw new Error('Open the Dakota Unison product page first.');
 const items=${jsonEncode(items.map((r) => {'sku': r['sku'], 'quantity': r['quantity']}).toList())};
 if(!items.length) throw new Error('Shopping list is empty.');
 const missing=[], ready=[];
 for(const item of items) {
   if(!/^UNS[A-Z]+[0-9]+\$/.test(item.sku)||!Number.isInteger(item.quantity)||item.quantity<1||item.quantity>99) throw new Error('Invalid shopping list.');
   const rows=Array.from(document.querySelectorAll('tr.sku'));
   const row=rows.find(r=>r.querySelector('.sku-code-inner')?.textContent.trim()===item.sku);
   const input=row?.querySelector('input.qty');
   if(!input || !row.querySelector('a.buy-sku')) missing.push(item.sku);
   else ready.push([input,item]);
 }
 if(missing.length && ${submit ? 'false' : 'true'}) return JSON.stringify({missing,submitted:false});
 if(!ready.length) return JSON.stringify({missing,submitted:false});
 const button=document.querySelector('a.add-to-cart');
 if(!button) throw new Error('Dakota cart controls changed. Nothing was added.');
 ${submit ? "if(window.__painterCartSent) throw new Error('Already submitted. Check Dakota cart before trying again.'); for(const input of document.querySelectorAll('tr.sku input.qty')) input.value=''; for(const [input,item] of ready) { input.value=String(item.quantity); input.dispatchEvent(new Event('change',{bubbles:true})); } window.__painterCartSent=true; button.click();" : ''}
 return JSON.stringify({missing,submitted:${submit ? 'true' : 'false'}});
})()
''';
