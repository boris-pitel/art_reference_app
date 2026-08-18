import 'dart:typed_data';

/// The generated thumbnail derivative plus the original image's pixel dimensions.
class ImageDerivatives {
  const ImageDerivatives({
    required this.thumbnailBytes,
    required this.width,
    required this.height,
  });

  final Uint8List thumbnailBytes;
  final int width;
  final int height;
}
