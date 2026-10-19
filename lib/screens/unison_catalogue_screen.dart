import '../services/unison_platform.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/dakota_stock.dart';
import '../services/unison_cart.dart';
import '../services/unison_catalogue.dart';
import '../widgets/dakota_stock_panel.dart';
import '../widgets/unison_cart_button.dart';
import '../widgets/unison_catalogue_list.dart';
import '../widgets/unison_photo_search_button.dart';
import 'unison_cart_screen.dart';
import 'unison_match_screen.dart';

class UnisonCatalogueScreen extends StatefulWidget {
  const UnisonCatalogueScreen({super.key, required this.userId});
  final String userId;
  @override
  State<UnisonCatalogueScreen> createState() => _UnisonCatalogueScreenState();
}

class _UnisonCatalogueScreenState extends State<UnisonCatalogueScreen> {
  late final _cart = UnisonCart(widget.userId);
  late Future<List<Map<String, dynamic>>> _catalogue;
  Map<String, DakotaOffer> _offers = {};
  Map<String, int> _quantities = {};
  bool _busy = false;
  bool get _usesCamera => defaultTargetPlatform == TargetPlatform.iOS;

  Future<Uint8List?> _capturePhoto() async {
    if (!_allowed) return null;
    FocusManager.instance.primaryFocus?.unfocus();
    final photo = await ImagePicker().pickImage(
      source: _usesCamera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.rear,
      maxWidth: 2000,
      maxHeight: 2000,
    );
    if (photo == null || !mounted || !_allowed) return null;
    final bytes = await photo.readAsBytes();
    return mounted && _allowed ? bytes : null;
  }

  Future<void> _matchPhoto(Uint8List bytes) async {
    if (!_allowed || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UnisonMatchScreen(loadImage: () async => bytes),
      ),
    );
  }

  bool get _allowed =>
      unisonPlatformAvailable &&
      Supabase.instance.client.auth.currentUser?.id == widget.userId &&
      Supabase.instance.client.auth.currentUser?.appMetadata['is_admin'] ==
          true;
  @override
  void initState() {
    super.initState();
    _catalogue = _load();
    UnisonCart.changes.addListener(_cartChanged);
    _cartChanged();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!_allowed) throw StateError('Administrator access required.');
    final data = await Supabase.instance.client
        .from('pastel_swatches')
        .select()
        .eq('brand', 'Unison');
    if (!_allowed) throw StateError('Account changed. Reopen this screen.');
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList()
      ..sort(compareUnisonCodes);
  }

  void _cartChanged() => unawaited(_loadQuantities());
  Future<void> _loadQuantities() async {
    try {
      final rows = await _cart.load();
      if (mounted && _allowed) {
        setState(
          () => _quantities = {
            for (final row in rows)
              row['sku'] as String: row['quantity'] as int,
          },
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to load cart: $error')));
      }
    }
  }

  Future<void> _change(Future<void> Function() action) async {
    if (!_allowed || _busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _loadQuantities();
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

  @override
  void dispose() {
    UnisonCart.changes.removeListener(_cartChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Browse Unison pastels'),
      actions: [
        UnisonCartButton(
          userId: widget.userId,
          onPressed: !_allowed
              ? null
              : () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => UnisonCartScreen(userId: widget.userId),
                  ),
                ),
        ),
      ],
    ),
    body: !_allowed
        ? const Center(child: Text('Administrator access required.'))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DakotaStockPanel(
                  onChanged: (offers) {
                    if (mounted) setState(() => _offers = offers);
                  },
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _catalogue,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Unable to load pastels: ${snapshot.error}'),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _catalogue = _load()),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return UnisonCatalogueList(
                      rows: snapshot.data!,
                      offers: _offers,
                      quantities: _quantities,
                      busy: _busy,
                      photoSearch: UnisonPhotoSearchButton(
                        capture: _capturePhoto,
                        openMatches: _matchPhoto,
                        enabled: _allowed && !_busy,
                        usesCamera: _usesCamera,
                      ),
                      onAdd: (row) => _change(() => _cart.add(row)),
                      onQuantity: (sku, qty) =>
                          _change(() => _cart.quantity(sku, qty)),
                    );
                  },
                ),
              ),
            ],
          ),
  );
}
