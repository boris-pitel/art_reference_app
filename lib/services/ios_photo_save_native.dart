import 'dart:typed_data';

/// Non-web platforms save through the system photo library directly.
class IosPhotoSave {
  const IosPhotoSave._();

  static Future<void> present(
    Uint8List bytes, {
    required String mimeType,
  }) async {}

  static void dismiss() {}
}
