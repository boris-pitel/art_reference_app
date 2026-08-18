import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

class ImageShareService {
  const ImageShareService._();

  static Future<void> share(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
