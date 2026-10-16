import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/unison_cart.dart';
import '../services/dakota_stock.dart';
import '../widgets/dakota_stock_panel.dart';
import 'dakota_cart_screen.dart';
import 'unison_catalogue_screen.dart';

class UnisonCartScreen extends StatefulWidget {
  const UnisonCartScreen({super.key, required this.userId});
  final String userId;
  @override
  State<UnisonCartScreen> createState() => _UnisonCartScreenState();
}

class _UnisonCartScreenState extends State<UnisonCartScreen> {
  late final UnisonCart _cart = UnisonCart(widget.userId);
  late Future<List<Map<String, dynamic>>> _rows;
  bool _busy = false;
  Map<String, DakotaOffer> _offers = {};

  Future<void> _browse() async {
    if (!_allowed || _busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UnisonCatalogueScreen(userId: widget.userId),
      ),
    );
    if (mounted && _allowed) setState(() => _rows = _cart.load());
  }

  String _details(Map<String, dynamic> row) {
    final offer = _offers[row['sku']] ?? const DakotaOffer();
    final price = offer.unitCents;
    return '${row['sku']} · ${offer.availability}\n${offer.priceLabel}'
        '${price == null ? '' : ' · ${row['quantity']} × ${usd(price)} = ${usd(price * (row['quantity'] as int))}'}';
  }

  final Map<String, Future<String>> _swatches = {};
  Future<String> _swatchUrl(Map<String, dynamic> row) async {
    if (!_allowed) throw StateError('Administrator access required.');
    final client = Supabase.instance.client;
    var path = row['swatch_path'] as String?;
    if (path == null) {
      final swatch = await client
          .from('pastel_swatches')
          .select('swatch_path')
          .eq('brand', 'Unison')
          .eq('retailer_sku', row['sku'])
          .single();
      path = swatch['swatch_path'] as String;
    }
    if (!_allowed) throw StateError('Account changed.');
    return client.storage.from('pastel-catalogue').createSignedUrl(path, 3600);
  }

  Future<void> _shop(List<Map<String, dynamic>> rows) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer to Dakota'),
        content: const Text(
          'This adds the selected quantities to your existing Dakota cart. Repeating a transfer can add duplicates. Review the cart at Dakota before ordering. Your local list will stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Dakota'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_allowed) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DakotaCartScreen(
          items: rows.map((r) => Map<String, dynamic>.from(r)).toList(),
        ),
      ),
    );
  }

  bool get _allowed =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      Supabase.instance.client.auth.currentUser?.id == widget.userId &&
      Supabase.instance.client.auth.currentUser?.appMetadata['is_admin'] ==
          true;
  @override
  void initState() {
    super.initState();
    _rows = _cart.load();
  }

  Future<void> _quantity(String sku, int quantity) async {
    if (!_allowed || _busy) return;
    setState(() => _busy = true);
    try {
      await _cart.quantity(sku, quantity);
      if (mounted) setState(() => _rows = _cart.load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to save cart: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (!_allowed || _busy) return;
    setState(() => _busy = true);
    try {
      await _cart.clear();
      if (mounted) setState(() => _rows = _cart.load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to clear cart: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Unison shopping cart')),
    body: !_allowed
        ? const Center(child: Text('Windows administrator access required.'))
        : FutureBuilder<List<Map<String, dynamic>>>(
            future: _rows,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Unable to load shopping cart: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Saved on this computer for your account. Add colours from image matches. Prices and availability are confirmed at Dakota.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DakotaStockPanel(
                      onChanged: (offers) {
                        if (mounted) setState(() => _offers = offers);
                      },
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text('Your shopping cart is empty.'),
                          )
                        : ListView(
                            children: [
                              for (final row in rows)
                                ListTile(
                                  leading: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: FutureBuilder<String>(
                                      future: _swatches.putIfAbsent(
                                        row['sku'] as String,
                                        () => _swatchUrl(row),
                                      ),
                                      builder: (context, snapshot) =>
                                          snapshot.hasData
                                          ? Image.network(
                                              snapshot.data!,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, _, _) =>
                                                  const Tooltip(
                                                    message:
                                                        'Swatch preview unavailable',
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                    ),
                                                  ),
                                            )
                                          : snapshot.hasError
                                          ? const Tooltip(
                                              message:
                                                  'Swatch preview unavailable',
                                              child: Icon(
                                                Icons.broken_image_outlined,
                                              ),
                                            )
                                          : const Center(
                                              child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            ),
                                    ),
                                  ),
                                  title: Text(
                                    '${row['code']} · ${row['name']}',
                                  ),
                                  subtitle: Text(_details(row)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Decrease quantity',
                                        onPressed: _busy
                                            ? null
                                            : () => _quantity(
                                                row['sku'] as String,
                                                (row['quantity'] as int) - 1,
                                              ),
                                        icon: const Icon(Icons.remove),
                                      ),
                                      Text('${row['quantity']}'),
                                      IconButton(
                                        tooltip: 'Increase quantity',
                                        onPressed:
                                            _busy ||
                                                (row['quantity'] as int) >= 99
                                            ? null
                                            : () => _quantity(
                                                row['sku'] as String,
                                                (row['quantity'] as int) + 1,
                                              ),
                                        icon: const Icon(Icons.add),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove colour',
                                        onPressed: _busy
                                            ? null
                                            : () => _quantity(
                                                row['sku'] as String,
                                                0,
                                              ),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DakotaCartEstimate(rows, _offers).label,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Before tax and shipping. Final prices are confirmed at Dakota.',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _browse,
                                icon: const Icon(Icons.palette_outlined),
                                label: const Text('Add pastels'),
                              ),
                              OutlinedButton.icon(
                                onPressed: rows.isEmpty || _busy
                                    ? null
                                    : _clear,
                                icon: const Icon(
                                  Icons.remove_shopping_cart_outlined,
                                ),
                                label: const Text('Clear cart'),
                              ),
                              OutlinedButton(
                                onPressed: rows.isEmpty
                                    ? null
                                    : () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: rows
                                                .map(
                                                  (r) =>
                                                      "${r['sku']} × ${r['quantity']} — ${r['name']}",
                                                )
                                                .join('\n'),
                                          ),
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Shopping list copied.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                child: const Text('Copy list'),
                              ),
                              FilledButton(
                                onPressed: rows.isEmpty || _busy
                                    ? null
                                    : () => _shop(rows),
                                child: const Text('Shop at Dakota'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
  );
}
