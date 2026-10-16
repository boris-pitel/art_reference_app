enum DakotaStock {
  inStock('In stock'),
  outOfStock('Out of stock'),
  discontinued('Discontinued'),
  unknown('Unknown');

  const DakotaStock(this.label);
  final String label;
}

int? parseDakotaPrice(Object? value) {
  final match = RegExp(
    r'^\s*\$([0-9]+(?:,[0-9]{3})*)\.([0-9]{2})\s*$',
  ).firstMatch(value?.toString() ?? '');
  if (match == null) return null;
  return int.parse(match[1]!.replaceAll(',', '')) * 100 + int.parse(match[2]!);
}

String usd(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

class DakotaOffer {
  const DakotaOffer({
    this.stock = DakotaStock.unknown,
    this.expected = '',
    this.unitCents,
    this.regularCents,
  });
  factory DakotaOffer.fromRow(Map<String, dynamic> row) => DakotaOffer(
    stock: classifyDakotaStock(row),
    expected: (row['expected'] as String? ?? '').trim(),
    unitCents: parseDakotaPrice(row['price']),
    regularCents: parseDakotaPrice(row['regularPrice']),
  );
  final DakotaStock stock;
  final String expected;
  final int? unitCents, regularCents;
  String get availability =>
      expected.isEmpty ? stock.label : '${stock.label} · $expected';
  bool get onSale =>
      unitCents != null && regularCents != null && regularCents! > unitCents!;
  String get priceLabel => unitCents == null
      ? 'Price unavailable'
      : '${onSale ? 'Sale ' : ''}${usd(unitCents!)} per stick${onSale ? ' (was ${usd(regularCents!)})' : ''}';
}

class DakotaCartEstimate {
  DakotaCartEstimate(
    List<Map<String, dynamic>> rows,
    Map<String, DakotaOffer> offers,
  ) {
    for (final row in rows) {
      final qty = row['quantity'] as int;
      final price = offers[row['sku']]?.unitCents;
      if (price == null) {
        unpricedSticks += qty;
      } else {
        knownCents += price * qty;
      }
    }
  }
  int knownCents = 0, unpricedSticks = 0;
  String get label => unpricedSticks == 0
      ? 'Estimated total: ${usd(knownCents)} USD'
      : 'Known-price subtotal: ${usd(knownCents)} USD · $unpricedSticks sticks unpriced';
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
   expected: row.querySelector('.oos-message')?.innerText || '',
   price: Array.from(row.querySelectorAll('td.price')).filter(cell => !cell.classList.contains('line-through') && !cell.classList.contains('base-price')).map(cell => cell.innerText.trim()).filter(Boolean).pop() || '',
   regularPrice: row.querySelector('.base-price')?.innerText || '',
   actions: row.querySelector('.actions')?.innerText || '',
   canBuy: !!row.querySelector('input.qty:not(:disabled)') && !!row.querySelector('a.buy-sku')
 })).filter(row => /^UNS[A-Z]+[0-9]+$/.test(row.sku || '')));
})()
''';
