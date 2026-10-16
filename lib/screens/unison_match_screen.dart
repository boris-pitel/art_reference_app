import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/unison_matching.dart';
import '../services/unison_cart.dart';
import 'unison_cart_screen.dart';

bool get unisonMatchingAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Map<String, Object> _prepare(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException('Unable to decode this image.');
  }
  image = img.bakeOrientation(image);
  if (math.max(image.width, image.height) > 2000) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 2000)
        : img.copyResize(image, height: 2000);
  }
  return {
    'width': image.width,
    'height': image.height,
    'pixels': image.getBytes(order: img.ChannelOrder.rgba),
    'png': Uint8List.fromList(img.encodePng(image)),
  };
}

class UnisonMatchScreen extends StatefulWidget {
  const UnisonMatchScreen({super.key, required this.loadImage});
  final Future<Uint8List> Function() loadImage;
  @override
  State<UnisonMatchScreen> createState() => _UnisonMatchScreenState();
}

class _UnisonMatchScreenState extends State<UnisonMatchScreen> {
  final _client = Supabase.instance.client;
  late Future<void> _loading;
  String? _owner;
  Map<String, Object>? _image;
  List<Map<String, dynamic>> _catalogue = [];
  List<Map<String, dynamic>> _matches = [];
  final Map<String, Future<String>> _urls = {};
  Color? _sample;
  Offset? _point;
  Future<void> _addToCart(Map<String, dynamic> row) async {
    if (!_allowed || _owner == null) return;
    try {
      await UnisonCart(_owner!).add(row);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${row['code']} added to shopping cart')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to add colour: $error')));
      }
    }
  }

  bool get _allowed =>
      unisonMatchingAvailable &&
      _client.auth.currentUser?.appMetadata['is_admin'] == true &&
      (_owner == null || _owner == _client.auth.currentUser?.id);

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<void> _load() async {
    if (!_allowed) throw StateError('Administrator access required.');
    _owner = _client.auth.currentUser!.id;
    final rows = await _client
        .from('pastel_swatches')
        .select()
        .eq('brand', 'Unison')
        .order('id');
    final prepared = await compute(_prepare, await widget.loadImage());
    if (!_allowed) throw StateError('Account changed. Reopen this tool.');
    _catalogue = rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    if (_catalogue.isEmpty) throw StateError('The Unison catalogue is empty.');
    _image = prepared;
  }

  void _pick(Offset point, Size display) {
    if (!_allowed || _image == null) return;
    final image = _image!,
        width = image['width'] as int,
        height = image['height'] as int;
    final pixels = image['pixels'] as Uint8List;
    final x = (point.dx / display.width * width).floor().clamp(0, width - 1);
    final y = (point.dy / display.height * height).floor().clamp(0, height - 1);
    var r = 0.0, g = 0.0, b = 0.0, n = 0;
    // A 5x5 patch on the displayed, orientation-corrected sampling image.
    for (var yy = math.max(0, y - 2); yy <= math.min(height - 1, y + 2); yy++) {
      for (
        var xx = math.max(0, x - 2);
        xx <= math.min(width - 1, x + 2);
        xx++
      ) {
        final index = (yy * width + xx) * 4;
        if (pixels[index + 3] == 0) continue;
        final alpha = pixels[index + 3] / 255;
        r += pixels[index] * alpha + 255 * (1 - alpha);
        g += pixels[index + 1] * alpha + 255 * (1 - alpha);
        b += pixels[index + 2] * alpha + 255 * (1 - alpha);
        n++;
      }
    }
    if (n == 0) return;
    r /= n;
    g /= n;
    b /= n;
    final lab = rgbToLab(r, g, b);
    final scored =
        _catalogue
            .map(
              (row) => {
                ...row,
                'distance': deltaE2000(lab, [
                  (row['lab_l'] as num).toDouble(),
                  (row['lab_a'] as num).toDouble(),
                  (row['lab_b'] as num).toDouble(),
                ]),
              },
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['distance'] as double).compareTo(b['distance'] as double),
          );
    setState(() {
      _sample = Color.fromARGB(255, r.round(), g.round(), b.round());
      _point = Offset(point.dx / display.width, point.dy / display.height);
      _matches = scored.take(3).toList();
    });
  }

  Widget _results() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Unison · admin experiment',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const Text(
          'Tap the image to sample a small area. Pinch or scroll to zoom. Matches use the original colours, without viewer overlays. Scan colours are approximate. Names are from Dakota. Tap a match or its cart icon to add a stick.',
        ),
        if (_sample != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(width: 40, height: 32, color: _sample),
                const SizedBox(width: 12),
                const Text('Sampled colour'),
              ],
            ),
          ),
        for (final row in _matches)
          Card(
            child: ListTile(
              onTap: () => _addToCart(row),
              leading: SizedBox(
                width: 48,
                height: 48,
                child: FutureBuilder<String>(
                  future: _urls.putIfAbsent(
                    row['swatch_path'] as String,
                    () => _client.storage
                        .from('pastel-catalogue')
                        .createSignedUrl(row['swatch_path'] as String, 3600),
                  ),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.network(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image),
                        )
                      : Icon(
                          snapshot.hasError
                              ? Icons.broken_image
                              : Icons.palette_outlined,
                        ),
                ),
              ),
              title: Text('${row['code']} · ${row['display_name']}'),
              subtitle: Text(
                'ΔE00 ${(row['distance'] as double).toStringAsFixed(1)}${row['verification_status'] == 'label_needs_review' ? ' · Label needs review' : ''}',
              ),
              trailing: IconButton(
                tooltip: 'Add to shopping cart',
                onPressed: () => _addToCart(row),
                icon: const Icon(Icons.add_shopping_cart),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Match Unison colour'),
      actions: [
        IconButton(
          tooltip: 'Shopping cart',
          icon: const Icon(Icons.shopping_cart_outlined),
          onPressed: _allowed && _owner != null
              ? () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => UnisonCartScreen(userId: _owner!),
                  ),
                )
              : null,
        ),
      ],
    ),
    body: FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Unable to load matching tool: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: () => setState(() => _loading = _load()),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!_allowed) {
          return const Center(child: Text('Administrator access required.'));
        }
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final preview = Expanded(
                child: ColoredBox(
                  color: Colors.black,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final size = applyBoxFit(
                        BoxFit.contain,
                        Size(
                          (_image!['width'] as int).toDouble(),
                          (_image!['height'] as int).toDouble(),
                        ),
                        box.biggest,
                      ).destination;
                      return Center(
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 8,
                          child: GestureDetector(
                            onTapUp: (details) =>
                                _pick(details.localPosition, size),
                            child: SizedBox(
                              width: size.width,
                              height: size.height,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.memory(
                                      _image!['png'] as Uint8List,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                  if (_point != null)
                                    Positioned(
                                      left: _point!.dx * size.width - 10,
                                      top: _point!.dy * size.height - 10,
                                      child: IgnorePointer(
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black,
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
              return constraints.maxWidth > constraints.maxHeight
                  ? Row(
                      children: [
                        preview,
                        SizedBox(width: 340, child: _results()),
                      ],
                    )
                  : Column(
                      children: [
                        preview,
                        SizedBox(
                          height: math.min(310, constraints.maxHeight * .48),
                          child: _results(),
                        ),
                      ],
                    );
            },
          ),
        );
      },
    ),
  );
}
