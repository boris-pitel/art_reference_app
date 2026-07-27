import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ThumbnailService {
  const ThumbnailService._();

  static Future<Uint8List> createThumbnail(
    Uint8List originalBytes, {
    int maximumDimension = 500,
    int jpegQuality = 80,
  }) async {
    final originalImage = img.decodeImage(originalBytes);

    if (originalImage == null) {
      throw const FormatException(
        'The selected file could not be decoded as an image.',
      );
    }

    final correctedImage = img.bakeOrientation(originalImage);

    final thumbnail = img.copyResize(
      correctedImage,
      width: correctedImage.width >= correctedImage.height
          ? maximumDimension
          : null,
      height: correctedImage.height > correctedImage.width
          ? maximumDimension
          : null,
      interpolation: img.Interpolation.average,
    );

    final encodedThumbnail = img.encodeJpg(thumbnail, quality: jpegQuality);

    return Uint8List.fromList(encodedThumbnail);
  }
}
