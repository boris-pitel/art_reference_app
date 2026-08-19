// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('navigator')
external JSObject get _navigator;

@JS('File')
extension type _JsFile._(JSObject _) implements JSObject {
  external factory _JsFile(JSArray<JSAny> parts, String name, JSObject options);
}

/// Hands a file to the iOS share sheet from inside a user gesture.
///
/// Safari only honours `navigator.share` while the page holds transient user
/// activation, and awaiting a network fetch spends it. Everything that needs
/// fetching must therefore happen first, and [shareBytes] must then be called
/// synchronously from a fresh tap — never after an `await`.
class GestureShare {
  const GestureShare._();

  /// True on mobile browsers that can share files.
  ///
  /// A browser download can only write to the downloads directory — no web API
  /// reaches the photo library — so the share sheet is the only route into
  /// Photos or the gallery. Desktop keeps the plain download, where a file on
  /// disk is what is wanted anyway.
  static bool get isRequired =>
      (_isIos || _isAndroid) &&
      _navigator.has('share') &&
      _navigator.has('canShare');

  /// Whether this is an iOS browser, whose Photos import has its own limits.
  static bool get isIosBrowser => _isIos;

  static bool get _isAndroid =>
      html.window.navigator.userAgent.contains('Android');

  static void shareBytes(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) {
    final options = JSObject();
    options.setProperty('type'.toJS, mimeType.toJS);

    final file = _JsFile(<JSAny>[bytes.toJS].toJS, fileName, options);

    final data = JSObject();
    data.setProperty('files'.toJS, <JSAny>[file].toJS);

    if (_navigator.callMethod<JSBoolean>('canShare'.toJS, data).toDart !=
        true) {
      return;
    }

    // The promise is deliberately not awaited: awaiting would not give the
    // caller anything useful (the sheet reports its own outcome) and this must
    // stay synchronous with respect to the gesture. A rejection handler is
    // attached so a dismissed sheet does not surface as an uncaught error.
    _navigator
        .callMethod<JSPromise<JSAny?>>('share'.toJS, data)
        .toDart
        .catchError((Object _) => null);
  }

  /// iPadOS 13+ reports a desktop user agent, so touch support is what
  /// separates it from a real Mac.
  static bool get _isIos {
    final navigator = html.window.navigator;
    final userAgent = navigator.userAgent;

    if (userAgent.contains('iPhone') ||
        userAgent.contains('iPad') ||
        userAgent.contains('iPod')) {
      return true;
    }

    return userAgent.contains('Macintosh') &&
        (navigator.maxTouchPoints ?? 0) > 1;
  }
}
