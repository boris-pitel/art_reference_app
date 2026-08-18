import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_derivatives.dart';

class ThumbnailService {
  const ThumbnailService._();

  static Future<ImageDerivatives> createDerivatives(
    Uint8List originalBytes, {
    int thumbnailMaxDimension = 500,
    int thumbnailJpegQuality = 80,
  }) async {
    final originalImage = img.decodeImage(originalBytes);

    if (originalImage == null) {
      throw const FormatException(
        'The selected file could not be decoded as an image.',
      );
    }

    final correctedImage = img.bakeOrientation(originalImage);

    final longestSide = math.max(correctedImage.width, correctedImage.height);

    // An image already within the cap is used as-is. Resizing it anyway would
    // upscale it, producing a blurrier thumbnail that is larger than the source.
    final thumbnail = longestSide <= thumbnailMaxDimension
        ? correctedImage
        : img.copyResize(
            correctedImage,
            width: correctedImage.width >= correctedImage.height
                ? thumbnailMaxDimension
                : null,
            height: correctedImage.height > correctedImage.width
                ? thumbnailMaxDimension
                : null,
            interpolation: img.Interpolation.average,
          );
    final thumbnailBytes = Uint8List.fromList(
      img.encodeJpg(thumbnail, quality: thumbnailJpegQuality),
    );

    return ImageDerivatives(
      thumbnailBytes: thumbnailBytes,
      width: correctedImage.width,
      height: correctedImage.height,
    );
  }
}
