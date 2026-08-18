import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class ImageShareService {
  const ImageShareService._();

  /// Shares [bytes] as an image file.
  ///
  /// The bytes are written to a real temp file first. Passing XFile.fromData
  /// instead would break sharing on Windows: cross_file ignores its `name`
  /// argument on non-web, and share_plus builds its own temp path with forward
  /// slashes, which the WinRT share API rejects — silently, producing an empty
  /// share sheet.
  static Future<void> share(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    final tempDirectory = await getTemporaryDirectory();

    final separator = Platform.pathSeparator;

    final fileDirectory = Directory(
      '${tempDirectory.path}$separator${const Uuid().v4()}',
    );

    await fileDirectory.create(recursive: true);

    final filePath = '${fileDirectory.path}$separator$fileName';

    await File(filePath).writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: mimeType)],
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
