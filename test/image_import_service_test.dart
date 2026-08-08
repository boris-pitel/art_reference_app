import 'dart:typed_data';

import 'package:art_reference_app/services/image_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageImportService.isHeif', () {
    test('recognizes HEIC and HEIF-compatible brands', () {
      for (final brand in ['heic', 'heix', 'mif1', 'msf1']) {
        final bytes = Uint8List.fromList([
          0,
          0,
          0,
          24,
          ...'ftyp'.codeUnits,
          ...brand.codeUnits,
        ]);

        expect(ImageImportService.isHeif(bytes), isTrue, reason: brand);
      }
    });

    test('does not classify JPEG or truncated data as HEIF', () {
      expect(
        ImageImportService.isHeif(Uint8List.fromList([0xff, 0xd8, 0xff])),
        isFalse,
      );
      expect(ImageImportService.isHeif(Uint8List(0)), isFalse);
    });
  });
}
