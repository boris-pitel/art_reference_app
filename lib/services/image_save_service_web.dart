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

    // The anchor and its object URL both outlive the click. Removing either in
    // the same turn can cancel a download that has not started transferring
    // yet — which a small file survives, because it starts immediately, and a
    // large one does not.
    Future.delayed(const Duration(minutes: 1), () {
      anchor.remove();
      html.Url.revokeObjectUrl(url);
    });

    return const ImageSaveResult.downloaded();
  }
}
