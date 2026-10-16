import 'dart:io';
import 'package:art_reference_app/services/unison_cart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'partial transfer adds available colours and all-unavailable submits nothing',
    () async {
      final items = [
        {'sku': 'UNSBE14', 'quantity': 2},
        {'sku': 'UNSGREY17', 'quantity': 1},
      ];
      final result = await Process.run('node', [
        '-e',
        '''
const assert=require('node:assert/strict');
const window={},location={origin:'https://dakotapastels.com',pathname:'/products/Soft-Unison-Individual'};
class Event {constructor(type,options){}}
let clicks=0,available=true;
const input={value:'',dispatchEvent(){}};
const row={querySelector(s){return s==='.sku-code-inner'?{textContent:'UNSBE14'}:s==='input.qty'&&available?input:s==='a.buy-sku'&&available?{}:null;}};
const document={querySelectorAll(s){return s==='tr.sku'?[row]:[input]},querySelector(){return {click(){clicks++}}}};
const check=${dakotaCartScript(items)};
assert.deepEqual(JSON.parse(check).missing,['UNSGREY17']);assert.equal(clicks,0);assert.equal(input.value,'');
const sent=${dakotaCartScript(items, submit: true)};
assert.equal(JSON.parse(sent).submitted,true);assert.equal(input.value,'2');assert.equal(clicks,1);
delete window.__painterCartSent;available=false;
const none=${dakotaCartScript(items, submit: true)};
assert.equal(JSON.parse(none).submitted,false);assert.equal(clicks,1);
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
  test(
    'Dakota adapter fills only selected quantities and submits once',
    () async {
      final script = dakotaCartScript([
        {'sku': 'UNSBE14', 'quantity': 2},
      ], submit: true);
      final result = await Process.run('node', [
        '-e',
        '''
const assert=require('node:assert/strict');
const window={},location={origin:'https://dakotapastels.com',pathname:'/products/Soft-Unison-Individual'};
class Event {constructor(type,options){}}
let clicks=0;
const input={value:'',dispatchEvent(){}},other={value:'7',dispatchEvent(){}};
const row={querySelector(s){return s==='.sku-code-inner'?{textContent:'UNSBE14'}:s==='input.qty'?input:s==='a.buy-sku'?{}:null;}};
const document={querySelectorAll(s){return s==='tr.sku'?[row]:[input,other]},querySelector(){return {click(){clicks++}}}};
const result=$script;
assert.equal(JSON.parse(result).submitted,true);
assert.equal(input.value,'2');assert.equal(other.value,'');assert.equal(clicks,1);
assert.throws(()=>{ $script },/Already submitted/);
assert.equal(clicks,1);
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const row = {
    'code': 'BE14',
    'retailer_sku': 'UNSBE14',
    'display_name': 'Unison Brown Earth 14',
  };
  test(
    'merges duplicates, persists across instances, isolates accounts',
    () async {
      final a = UnisonCart('a');
      await Future.wait([a.add(row), a.add(row)]);
      expect((await UnisonCart('a').load()).single['quantity'], 2);
      expect(await UnisonCart('b').load(), isEmpty);
      await a.quantity('UNSBE14', 3);
      expect((await a.load()).single['quantity'], 3);
      await a.quantity('UNSBE14', 0);
      expect(await a.load(), isEmpty);
    },
  );
  test('rejects invalid SKU and quantity', () async {
    final cart = UnisonCart('a');
    expect(() => cart.add({...row, 'retailer_sku': 'bad'}), throwsStateError);
    expect(() => cart.quantity('UNSBE14', 100), throwsRangeError);
  });
  test('export script targets only product page and never checkout', () {
    final script = dakotaCartScript([
      {'sku': 'UNSBE14', 'quantity': 2},
    ], submit: true);
    expect(script, contains('location.origin'));
    expect(script, contains('Soft-Unison-Individual'));
    expect(script, contains('window.__painterCartSent'));
    expect(script, contains('button.click()'));
  });
}
