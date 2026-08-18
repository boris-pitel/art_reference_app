import 'dart:typed_data';

/// Pixel dimensions read straight from an image file's header.
class ImageDimensions {
  const ImageDimensions({required this.width, required this.height});

  final int width;
  final int height;

  int get megapixels => (width * height) ~/ 1000000;
}

/// Reads dimensions from JPEG and PNG headers without decoding the image.
///
/// Decoding is the expensive, memory-hungry step this exists to help avoid, so
/// it must never be the thing that triggers it. Both formats carry their size
/// within the first few hundred bytes.
class ImageDimensionsReader {
  const ImageDimensionsReader._();

  static ImageDimensions? read(Uint8List bytes) {
    final png = _readPng(bytes);
    if (png != null) return png;

    return _readJpeg(bytes);
  }

  /// PNG stores width and height as big-endian 32-bit values in the IHDR
  /// chunk, always at a fixed offset.
  static ImageDimensions? _readPng(Uint8List bytes) {
    if (bytes.length < 24) return null;

    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return null;
    }

    final data = ByteData.sublistView(bytes);

    return ImageDimensions(
      width: data.getUint32(16),
      height: data.getUint32(20),
    );
  }

  /// JPEG is a chain of marker segments; the dimensions live in whichever
  /// Start Of Frame marker the file uses, which has to be walked to.
  static ImageDimensions? _readJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

    var offset = 2;

    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }

      final marker = bytes[offset + 1];

      // Standalone markers carry no length field.
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        offset += 2;
        continue;
      }

      // Start Of Scan — image data begins, so the header is behind us.
      if (marker == 0xDA) return null;

      final segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
      if (segmentLength < 2) return null;

      // SOF0 through SOF15, excluding the DHT, JPG and DAC markers that fall
      // inside the same numeric range.
      final isStartOfFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;

      if (isStartOfFrame) {
        if (offset + 9 >= bytes.length) return null;

        return ImageDimensions(
          height: (bytes[offset + 5] << 8) | bytes[offset + 6],
          width: (bytes[offset + 7] << 8) | bytes[offset + 8],
        );
      }

      offset += 2 + segmentLength;
    }

    return null;
  }
}
