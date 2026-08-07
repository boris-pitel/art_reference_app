import 'dart:typed_data';

import 'package:gal/gal.dart';

class ImageSaveService {
  const ImageSaveService._();

  static Future<void> save(Uint8List bytes, {required String fileName}) async {
    var hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      hasAccess = await Gal.requestAccess();
    }
    if (!hasAccess) {
      throw StateError('Permission to save images was not granted.');
    }
    await Gal.putImageBytes(bytes);
  }
}
