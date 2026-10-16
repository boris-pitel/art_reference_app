import 'package:flutter/material.dart';
import '../services/dakota_stock.dart';
import '../services/unison_catalogue.dart';
import 'unison_swatch.dart';

class UnisonCatalogueList extends StatefulWidget {
  const UnisonCatalogueList({
    super.key,
    required this.rows,
    required this.offers,
    required this.quantities,
    required this.onAdd,
    required this.onQuantity,
    this.busy = false,
  });
  final List<Map<String, dynamic>> rows;
  final Map<String, DakotaOffer> offers;
  final Map<String, int> quantities;
  final ValueChanged<Map<String, dynamic>> onAdd;
  final void Function(String sku, int quantity) onQuantity;
  final bool busy;
  @override
  State<UnisonCatalogueList> createState() => _UnisonCatalogueListState();
}

class _UnisonCatalogueListState extends State<UnisonCatalogueList> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = searchUnisonCatalogue(widget.rows, _search.text);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Search by code or name…',
              hintText: 'BE14, Brown Earth, Grey…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${rows.length} pastels'),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No pastels match your search.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index],
                        sku = row['retailer_sku'] as String? ?? '';
                    final offer = widget.offers[sku] ?? const DakotaOffer();
                    final qty = widget.quantities[sku] ?? 0;
                    return Card(
                      key: ValueKey(sku),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UnisonSwatch(path: row['swatch_path'] as String?),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${row['code']} · ${row['display_name']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(sku),
                                  Text(offer.availability),
                                  Text(offer.priceLabel),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (qty == 0)
                              FilledButton.icon(
                                onPressed: widget.busy || sku.isEmpty
                                    ? null
                                    : () => widget.onAdd(row),
                                icon: const Icon(Icons.add_shopping_cart),
                                label: const Text('Add'),
                              )
                            else
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('✓ In cart · $qty'),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Decrease ${row['code']}',
                                        onPressed: widget.busy
                                            ? null
                                            : () => widget.onQuantity(
                                                sku,
                                                qty - 1,
                                              ),
                                        icon: const Icon(Icons.remove),
                                      ),
                                      IconButton(
                                        tooltip: 'Increase ${row['code']}',
                                        onPressed: widget.busy || qty >= 99
                                            ? null
                                            : () => widget.onQuantity(
                                                sku,
                                                qty + 1,
                                              ),
                                        icon: const Icon(Icons.add),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
