import 'dart:typed_data';

/// Non-web platforms print through the platform's own print service.
class WebPrint {
  const WebPrint._();

  static Future<bool> printImage(
    Uint8List bytes, {
    required String mimeType,
  }) async => false;
}
