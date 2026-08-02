// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

class ImageSaveService {
  const ImageSaveService._();

  static Future<void> save(Uint8List bytes, {required String fileName}) async {
    final blob = html.Blob(<Object>[bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    try {
      html.AnchorElement(href: url)
        ..download = fileName
        ..click();
    } finally {
      html.Url.revokeObjectUrl(url);
    }
  }
}
