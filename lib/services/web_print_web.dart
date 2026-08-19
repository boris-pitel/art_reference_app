// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('document')
external JSObject get _document;

@JS('URL.createObjectURL')
external String _createObjectUrl(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

/// Prints an image through the browser's own print dialog.
///
/// The printing package refuses the print path for a mobile user agent and
/// falls back to opening a PDF, which Android turns into a download and an
/// "open with" chooser — never a printer. Chrome on Android will print an
/// ordinary page, so this prints one containing just the image.
class WebPrint {
  const WebPrint._();

  static const _frameId = '__painter_reference_print_frame__';

  static Future<bool> printImage(
    Uint8List bytes, {
    required String mimeType,
  }) async {
    final options = JSObject();
    options.setProperty('type'.toJS, mimeType.toJS);

    final url = _createObjectUrl(_Blob(<JSAny>[bytes.toJS].toJS, options));

    _removeFrame();

    final frame = _document.callMethod<JSObject>(
      'createElement'.toJS,
      'iframe'.toJS,
    );

    frame.setProperty('id'.toJS, _frameId.toJS);
    frame.getProperty<JSObject>('style'.toJS).setProperty(
      'cssText'.toJS,
      'position:fixed;right:0;bottom:0;width:1px;height:1px;opacity:0;border:none;'
          .toJS,
    );

    _document
        .getProperty<JSObject>('body'.toJS)
        .callMethod<JSAny?>('appendChild'.toJS, frame);

    try {
      final document = frame.getProperty<JSObject?>('contentDocument'.toJS);
      final window = frame.getProperty<JSObject?>('contentWindow'.toJS);

      if (document == null || window == null) return false;

      document.callMethod<JSAny?>('open'.toJS);
      document.callMethod<JSAny?>('write'.toJS, _pageHtml(url).toJS);
      document.callMethod<JSAny?>('close'.toJS);

      // Printing before the image has decoded would produce a blank sheet.
      if (!await _awaitImage(document)) return false;

      window.callMethod<JSAny?>('focus'.toJS);
      window.callMethod<JSAny?>('print'.toJS);

      return true;
    } finally {
      // Kept alive briefly: tearing the frame down while the print dialog is
      // still reading from it cancels the job in some browsers.
      Future.delayed(const Duration(minutes: 2), () {
        _removeFrame();
        _revokeObjectUrl(url);
      });
    }
  }

  static String _pageHtml(String url) {
    return '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      @page { margin: 10mm; }
      html, body { margin: 0; padding: 0; }
      img { display: block; margin: 0 auto; max-width: 100%; max-height: 100vh; }
    </style>
  </head>
  <body><img id="sheet" src="$url"></body>
</html>
''';
  }

  /// Polls rather than listening across the frame boundary, which keeps the
  /// interop to property reads.
  ///
  /// A decode that never completes is treated as failure: a very large photo
  /// can exceed what the browser will decode, and hanging on a print that will
  /// never arrive is worse than saying so.
  static Future<bool> _awaitImage(JSObject document) async {
    for (var elapsed = 0; elapsed < 20000; elapsed += 100) {
      final image = document.callMethod<JSObject?>(
        'getElementById'.toJS,
        'sheet'.toJS,
      );

      if (image != null) {
        final complete =
            image.getProperty<JSBoolean?>('complete'.toJS)?.toDart ?? false;

        if (complete) {
          final width =
              image.getProperty<JSNumber?>('naturalWidth'.toJS)?.toDartInt ?? 0;

          return width > 0;
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    return false;
  }

  static void _removeFrame() {
    final existing = _document.callMethod<JSObject?>(
      'getElementById'.toJS,
      _frameId.toJS,
    );

    existing?.callMethod<JSAny?>('remove'.toJS);
  }
}
