import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart' as ios;
import 'package:webview_windows/webview_windows.dart' as win;

enum RetailerLoadingState { loading, navigationCompleted }

/// A normal WebView on each supported platform; no background HTTP scraping.
class RetailerWebController {
  win.WebviewController? _windows;
  ios.WebViewController? _iphone;
  final _url = StreamController<String>.broadcast();
  final _loading = StreamController<RetailerLoadingState>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;
  Stream<String> get url => _url.stream;
  Stream<RetailerLoadingState> get loadingState => _loading.stream;
  Stream<Object> get onLoadError => _errors.stream;

  static Future<String?> getWebViewVersion() async =>
      defaultTargetPlatform == TargetPlatform.windows
      ? win.WebviewController.getWebViewVersion()
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'WKWebView'
      : defaultTargetPlatform == TargetPlatform.android
      ? 'Android WebView'
      : null;

  Future<void> initialize() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final web = _windows = win.WebviewController();
      await web.initialize();
      if (_disposed) {
        await web.dispose();
        return;
      }
      _subscriptions.add(
        web.url.listen((value) {
          if (!_disposed) _url.add(value);
        }),
      );
      _subscriptions.add(
        web.loadingState.listen((value) {
          if (_disposed) return;
          if (value == win.LoadingState.loading) {
            _loading.add(RetailerLoadingState.loading);
          }
          if (value == win.LoadingState.navigationCompleted) {
            _loading.add(RetailerLoadingState.navigationCompleted);
          }
        }),
      );
      _subscriptions.add(
        web.onLoadError.listen((value) {
          if (!_disposed) _errors.add(value);
        }),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      final web = _iphone = ios.WebViewController();
      await web.setJavaScriptMode(ios.JavaScriptMode.unrestricted);
      await web.setNavigationDelegate(
        ios.NavigationDelegate(
          onPageStarted: (url) {
            if (_disposed) return;
            _url.add(url);
            _loading.add(RetailerLoadingState.loading);
          },
          onPageFinished: (url) {
            if (_disposed) return;
            _url.add(url);
            _loading.add(RetailerLoadingState.navigationCompleted);
          },
          onWebResourceError: (error) {
            if (!_disposed && error.isForMainFrame == true) _errors.add(error);
          },
        ),
      );
    } else {
      throw UnsupportedError(
        'Dakota browsing requires Windows, iPhone or Android.',
      );
    }
  }

  Future<void> loadUrl(String url) async {
    if (_windows != null) {
      await _windows!.loadUrl(url);
    } else {
      await _iphone!.loadRequest(Uri.parse(url));
    }
  }

  Future<Object?> executeScript(String script) async {
    if (_windows != null) return _windows!.executeScript(script);
    // Both mobile WebViews return JSON.stringify results as a Dart String.
    final result = await _iphone!.runJavaScriptReturningResult(script);
    return result is String ? result : jsonEncode(result);
  }

  Future<void> reload() async {
    if (_windows != null) {
      await _windows!.reload();
    } else {
      await _iphone!.reload();
    }
  }

  Future<void> goBack() async {
    if (_windows != null) {
      await _windows!.goBack();
    } else if (await _iphone!.canGoBack()) {
      await _iphone!.goBack();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    if (_windows != null) await _windows!.dispose();
    await _url.close();
    await _loading.close();
    await _errors.close();
  }
}

class RetailerWebView extends StatelessWidget {
  const RetailerWebView(this.controller, {super.key});
  final RetailerWebController controller;
  @override
  Widget build(BuildContext context) => controller._windows != null
      ? win.Webview(controller._windows!)
      : ios.WebViewWidget(controller: controller._iphone!);
}
