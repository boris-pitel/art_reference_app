import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

class ThumbnailService {
  const ThumbnailService._();

  static Future<Uint8List> createThumbnail(
    Uint8List originalBytes, {
    int maximumDimension = 500,
    int jpegQuality = 80,
  }) async {
    if (originalBytes.isEmpty) {
      throw const FormatException('The selected image file is empty.');
    }

    if (maximumDimension <= 0) {
      throw ArgumentError.value(
        maximumDimension,
        'maximumDimension',
        'The maximum dimension must be greater than zero.',
      );
    }

    if (jpegQuality < 1 || jpegQuality > 100) {
      throw ArgumentError.value(
        jpegQuality,
        'jpegQuality',
        'JPEG quality must be between 1 and 100.',
      );
    }

    final contentType = _detectContentType(originalBytes);

    if (contentType == null) {
      throw const FormatException(
        'Only JPEG and PNG images are currently supported.',
      );
    }

    final blob = html.Blob(<Object>[originalBytes], contentType);

    final objectUrl = html.Url.createObjectUrlFromBlob(blob);

    try {
      final imageElement = html.ImageElement();

      await _loadImage(imageElement, objectUrl);

      final originalWidth = imageElement.naturalWidth;
      final originalHeight = imageElement.naturalHeight;

      if (originalWidth <= 0 || originalHeight <= 0) {
        throw const FormatException(
          'The selected image has invalid dimensions.',
        );
      }

      final dimensions = _calculateThumbnailDimensions(
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        maximumDimension: maximumDimension,
      );

      final canvas = html.CanvasElement(
        width: dimensions.width,
        height: dimensions.height,
      );

      final context = canvas.context2D;

      context.drawImageScaled(
        imageElement,
        0,
        0,
        dimensions.width,
        dimensions.height,
      );

      final dataUrl = canvas.toDataUrl('image/jpeg', jpegQuality / 100);

      final commaIndex = dataUrl.indexOf(',');

      if (commaIndex < 0 || commaIndex == dataUrl.length - 1) {
        throw const FormatException(
          'The browser produced an invalid thumbnail.',
        );
      }

      final encodedData = dataUrl.substring(commaIndex + 1);
      final decodedBytes = base64Decode(encodedData);

      if (decodedBytes.isEmpty) {
        throw const FormatException('The browser produced an empty thumbnail.');
      }

      return Uint8List.fromList(decodedBytes);
    } finally {
      html.Url.revokeObjectUrl(objectUrl);
    }
  }

  static Future<void> _loadImage(
    html.ImageElement imageElement,
    String objectUrl,
  ) async {
    final completer = Completer<void>();

    late final StreamSubscription<html.Event> loadSubscription;
    late final StreamSubscription<html.Event> errorSubscription;

    loadSubscription = imageElement.onLoad.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    errorSubscription = imageElement.onError.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          const FormatException('Chrome could not decode the selected image.'),
        );
      }
    });

    imageElement.src = objectUrl;

    try {
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(
            'Chrome took too long to decode the selected image.',
          );
        },
      );
    } finally {
      await loadSubscription.cancel();
      await errorSubscription.cancel();
    }
  }

  static _ThumbnailDimensions _calculateThumbnailDimensions({
    required int originalWidth,
    required int originalHeight,
    required int maximumDimension,
  }) {
    if (originalWidth <= maximumDimension &&
        originalHeight <= maximumDimension) {
      return _ThumbnailDimensions(width: originalWidth, height: originalHeight);
    }

    if (originalWidth >= originalHeight) {
      final scaledHeight = (originalHeight * maximumDimension / originalWidth)
          .round();

      return _ThumbnailDimensions(
        width: maximumDimension,
        height: scaledHeight < 1 ? 1 : scaledHeight,
      );
    }

    final scaledWidth = (originalWidth * maximumDimension / originalHeight)
        .round();

    return _ThumbnailDimensions(
      width: scaledWidth < 1 ? 1 : scaledWidth,
      height: maximumDimension,
    );
  }

  static String? _detectContentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }

    return null;
  }
}

class _ThumbnailDimensions {
  const _ThumbnailDimensions({required this.width, required this.height});

  final int width;
  final int height;
}
