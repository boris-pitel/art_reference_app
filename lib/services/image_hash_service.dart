import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class ImageHashService {
  const ImageHashService._();

  static final Sha256 _sha256 = Sha256();

  static Future<String> calculateSha256(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(
        imageBytes,
        'imageBytes',
        'Cannot calculate a hash for an empty image.',
      );
    }

    final hash = await _sha256.hash(imageBytes);

    return _bytesToHex(hash.bytes);
  }

  static String _bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();

    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }

    return buffer.toString();
  }
}
