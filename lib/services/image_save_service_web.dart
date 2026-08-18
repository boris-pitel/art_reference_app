// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'gesture_share.dart';
import 'image_save_result.dart';

class ImageSaveService {
  const ImageSaveService._();

  /// Menu/tooltip wording for the save action. iOS goes through the system
  /// share sheet, where the user picks "Save Image"; elsewhere the browser
  /// downloads the file.
  static String get actionLabel =>
      GestureShare.isRequired ? 'Save image' : 'Download image';

  static Future<ImageSaveResult> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final blob = html.Blob(
      <Object>[bytes],
      fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
    );

    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..download = fileName
      ..style.display = 'none';

    // Some browsers ignore clicks on elements outside the document.
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();

    // Revoking in the same turn as the click can cancel the download before
    // the browser has finished reading the blob, so it is deferred.
    Future.delayed(
      const Duration(minutes: 1),
      () => html.Url.revokeObjectUrl(url),
    );

    return const ImageSaveResult.downloaded();
  }
}
