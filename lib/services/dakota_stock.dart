enum DakotaStock {
  inStock('In stock'),
  outOfStock('Out of stock'),
  discontinued('Discontinued'),
  unknown('Unknown');

  const DakotaStock(this.label);
  final String label;
}

/// Explicit retailer text takes priority over purchase controls. Missing or
/// unrecognised controls never prove that a colour is out of stock.
DakotaStock classifyDakotaStock(Map<String, dynamic> row) {
  final text = '${row['note'] ?? ''} ${row['actions'] ?? ''}'.toLowerCase();
  if (RegExp(r'\bdiscontinued\b').hasMatch(text)) {
    return DakotaStock.discontinued;
  }
  if (RegExp(
    r'notify\s*me|out\s+of\s+stock|sold\s*out|expected\s+approx',
  ).hasMatch(text)) {
    return DakotaStock.outOfStock;
  }
  if (row['canBuy'] == true) return DakotaStock.inStock;
  return DakotaStock.unknown;
}

const dakotaProductUrl =
    'https://dakotapastels.com/products/Soft-Unison-Individual';

/// Reads only the public catalogue DOM. No cart changes or network scripts.
const dakotaStockScript = r'''
(() => {
 if(location.origin !== 'https://dakotapastels.com' || location.pathname !== '/products/Soft-Unison-Individual') return JSON.stringify([]);
 return JSON.stringify(Array.from(document.querySelectorAll('tr.sku')).filter(row => row.querySelector('.sku-name')).map(row => ({
   sku: row.querySelector('.sku-code-inner')?.textContent.trim(),
   note: row.querySelector('.sku-name')?.innerText || '',
   actions: row.querySelector('.actions')?.innerText || '',
   canBuy: !!row.querySelector('input.qty:not(:disabled)') && !!row.querySelector('a.buy-sku')
 })).filter(row => /^UNS[A-Z]+[0-9]+$/.test(row.sku || '')));
})()
''';
