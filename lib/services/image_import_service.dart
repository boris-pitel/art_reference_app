import 'dart:typed_data';

import 'package:platform_image_converter/platform_image_converter.dart';

class ImageImportService {
  const ImageImportService._();

  static const Set<String> _heifBrands = {
    'heic',
    'heix',
    'hevc',
    'hevx',
    'heim',
    'heis',
    'hevm',
    'hevs',
    'mif1',
    'msf1',
  };

  static bool isHeif(Uint8List bytes) {
    if (bytes.length < 12 ||
        bytes[4] != 0x66 ||
        bytes[5] != 0x74 ||
        bytes[6] != 0x79 ||
        bytes[7] != 0x70) {
      return false;
    }

    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    return _heifBrands.contains(brand);
  }

  static Future<Uint8List> normalizeForUpload(Uint8List bytes) async {
    if (!isHeif(bytes)) {
      return bytes;
    }

    return ImageConverter.convert(
      inputData: bytes,
      format: OutputFormat.jpeg,
      quality: 92,
      orientation: ExifOrientationPolicy.apply,
    );
  }
}
