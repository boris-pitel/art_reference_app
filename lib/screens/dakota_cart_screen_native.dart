import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/unison_cart.dart';

class DakotaCartScreen extends StatefulWidget {
  const DakotaCartScreen({super.key, required this.items});
  final List<Map<String, dynamic>> items;
  @override
  State<DakotaCartScreen> createState() => _DakotaCartScreenState();
}

class _DakotaCartScreenState extends State<DakotaCartScreen> {
  final _web = WebviewController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _ready = false, _loaded = false, _sent = false, _busy = false;
  String _message =
      'Loading Dakota. Your shopping list is kept in Painter Reference.';
  String _url = '';
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (await WebviewController.getWebViewVersion() == null) {
        throw StateError('Microsoft Edge WebView2 Runtime is required.');
      }
      await _web.initialize();
      if (!mounted) {
        await _web.dispose();
        return;
      }
      _subscriptions.add(
        _web.url.listen((url) {
          if (mounted) setState(() => _url = url);
        }),
      );
      _subscriptions.add(
        _web.loadingState.listen((state) {
          if (mounted) {
            setState(() => _loaded = state == LoadingState.navigationCompleted);
          }
        }),
      );
      _subscriptions.add(
        _web.onLoadError.listen((error) {
          if (mounted) {
            setState(
              () =>
                  _message = 'Dakota failed to load. Use Reload to try again.',
            );
          }
        }),
      );
      setState(() => _ready = true);
      await _web.loadUrl(
        'https://dakotapastels.com/products/Soft-Unison-Individual',
      );
    } catch (error) {
      if (mounted) setState(() => _message = 'Unable to open Dakota: $error');
    }
  }

  Future<void> _transfer() async {
    if (_sent || _busy) return;
    setState(() => _busy = true);
    try {
      // Latch before sending: an ambiguous network outcome must not auto-retry.
      final check = await _web.executeScript(dakotaCartScript(widget.items));
      final result = jsonDecode(check as String) as Map;
      final missing = result['missing'] as List;
      if (missing.isNotEmpty) {
        if (!mounted) return;
        final unavailable = widget.items
            .where((item) => missing.contains(item['sku']))
            .map((item) => '${item['code']} — ${item['name']}')
            .join('\n');
        final available = widget.items.length - missing.length;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Some colours are unavailable'),
            content: SingleChildScrollView(
              child: Text(
                '$unavailable\n\n${available > 0 ? '$available other colours can be added to Dakota.' : 'None of these colours can be added right now.'} Unavailable colours will remain in your Painter Reference cart.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep shopping list'),
              ),
              if (available > 0)
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Add available sticks'),
                ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
      _sent = true;
      final submitted =
          jsonDecode(
                await _web.executeScript(
                      dakotaCartScript(widget.items, submit: true),
                    )
                    as String,
              )
              as Map;
      if (submitted['submitted'] != true) {
        _sent = false;
        if (mounted) {
          setState(
            () => _message =
                'These colours are no longer available. Nothing was added. Your shopping list is saved.',
          );
        }
        return;
      }
      if (mounted) {
        setState(
          () => _message =
              'Available sticks sent to Dakota. Review the Dakota cart before ordering. Your local list, including unavailable colours, is retained.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              'Transfer issue: $error${_sent ? ' Check the Dakota cart before retrying to avoid duplicates.' : ''}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(_web.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dakota shopping cart'),
      actions: [
        IconButton(
          tooltip: 'View Dakota cart',
          onPressed: _ready && !_busy
              ? () => _web.loadUrl('https://dakotapastels.com/Checkout/Cart')
              : null,
          icon: const Icon(Icons.shopping_cart_outlined),
        ),
        IconButton(
          tooltip: 'Back',
          onPressed: _ready ? () => _web.goBack() : null,
          icon: const Icon(Icons.arrow_back),
        ),
        IconButton(
          tooltip: 'Reload',
          onPressed: _ready && !_busy ? () => _web.reload() : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_message),
              Text(_url, maxLines: 1, overflow: TextOverflow.ellipsis),
              FilledButton(
                onPressed: _ready && _loaded && !_sent && !_busy
                    ? _transfer
                    : null,
                child: Text(
                  _sent
                      ? 'Handed over to you'
                      : _busy
                      ? 'Transferring…'
                      : 'Add selected sticks to Dakota cart',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _ready
              ? Webview(_web)
              : const Center(child: Text('Preparing Dakota browser…')),
        ),
      ],
    ),
  );
}
