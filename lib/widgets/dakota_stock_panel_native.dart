import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/dakota_stock.dart';

class DakotaStockPanel extends StatefulWidget {
  const DakotaStockPanel({super.key, required this.onChanged});
  final ValueChanged<Map<String, DakotaOffer>> onChanged;
  @override
  State<DakotaStockPanel> createState() => _DakotaStockPanelState();
}

class _DakotaStockPanelState extends State<DakotaStockPanel> {
  final _web = WebviewController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _timeout, _expiry;
  bool _ready = false, _checking = true;
  int _generation = 0;
  String _message = 'Checking Dakota prices and stock…';

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _web.initialize();
      if (!mounted) {
        await _web.dispose();
        return;
      }
      _subscriptions.add(
        _web.loadingState.listen((state) {
          if (state == LoadingState.loading) {
            // An unrelated page must never retain stock from the previous page.
            _generation++;
            widget.onChanged({});
          }
          if (state == LoadingState.navigationCompleted) unawaited(_read());
        }),
      );
      _subscriptions.add(_web.onLoadError.listen((_) => _failed()));
      setState(() => _ready = true);
      await _refresh();
    } catch (_) {
      _failed();
    }
  }

  void _failed() {
    if (!mounted) return;
    _timeout?.cancel();
    _expiry?.cancel();
    widget.onChanged({});
    setState(() {
      _checking = false;
      _message =
          'Prices and stock unknown. Refresh or expand the Dakota page below.';
    });
  }

  Future<void> _refresh() async {
    if (!mounted || !_ready) return;
    _generation++;
    _expiry?.cancel();
    _timeout?.cancel();
    widget.onChanged({});
    setState(() {
      _checking = true;
      _message = 'Checking Dakota prices and stock…';
    });
    _timeout = Timer(const Duration(seconds: 30), _failed);
    try {
      await _web.loadUrl(dakotaProductUrl);
    } catch (_) {
      _failed();
    }
  }

  Future<void> _read() async {
    final generation = _generation;
    try {
      final raw = await _web.executeScript(dakotaStockScript);
      if (!mounted || generation != _generation) return;
      final rows = jsonDecode(raw as String) as List;
      if (rows.isEmpty) {
        _failed();
        return;
      }
      final stock = <String, DakotaOffer>{};
      for (final rawRow in rows) {
        final row = Map<String, dynamic>.from(rawRow as Map);
        stock[row['sku'] as String] = DakotaOffer.fromRow(row);
      }
      _timeout?.cancel();
      _expiry?.cancel();
      widget.onChanged(stock);
      final time = TimeOfDay.now().format(context);
      setState(() {
        _checking = false;
        _message = 'Dakota prices and stock checked at $time';
      });
      // Renew the public stock snapshot while this matching screen stays open.
      _expiry = Timer(const Duration(minutes: 5), () {
        if (!mounted) return;
        unawaited(_refresh());
      });
    } catch (_) {
      if (mounted && generation == _generation) _failed();
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _expiry?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_web.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(_message, style: Theme.of(context).textTheme.bodySmall),
          ),
          IconButton(
            tooltip: 'Refresh Dakota availability',
            onPressed: _ready && !_checking ? _refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (_ready)
        ExpansionTile(
          title: const Text('Dakota stock page'),
          maintainState: true,
          children: [SizedBox(height: 260, child: Webview(_web))],
        ),
    ],
  );
}
