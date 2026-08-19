import 'dart:typed_data';

/// Non-web platforms deliver files directly, so no gesture handoff is needed.
class GestureShare {
  const GestureShare._();

  static bool get isRequired => false;

  static bool get isIosBrowser => false;

  static void shareBytes(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
  }) {
    throw UnsupportedError(
      'GestureShare is only used on the web; check isRequired first.',
    );
  }
}
