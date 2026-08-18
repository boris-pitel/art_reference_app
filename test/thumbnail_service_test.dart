import 'dart:typed_data';

import 'package:art_reference_app/services/thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _syntheticJpeg(int width, int height) {
  final image = img.Image(width: width, height: height);
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  group('ThumbnailService.createDerivatives', () {
    test(
      'caps the thumbnail and reports true dimensions for an image far '
      'larger than any phone screen',
      () async {
        // Deliberately larger than the 6000x8000 photo that triggered a
        // blank-screen decode failure on the reporting device, so the
        // thumbnail cap is exercised regardless of how large the input gets.
        // (Kept well short of what a real 100+MP sensor could produce — much
        // bigger than this and the raw bitmap allocation trips the *test VM's*
        // own heap ceiling before it ever reaches the code under test.)
        final originalBytes = _syntheticJpeg(7500, 10000);

        final derivatives = await ThumbnailService.createDerivatives(
          originalBytes,
        );

        expect(derivatives.width, 7500);
        expect(derivatives.height, 10000);

        final decodedThumbnail = img.decodeImage(derivatives.thumbnailBytes);
        expect(decodedThumbnail, isNotNull);
        expect(decodedThumbnail!.width, lessThanOrEqualTo(500));
        expect(decodedThumbnail.height, lessThanOrEqualTo(500));
      },
    );

    test(
      'handles the exact reported failure size (6000x8000, 48MP)',
      () async {
        final originalBytes = _syntheticJpeg(6000, 8000);

        final derivatives = await ThumbnailService.createDerivatives(
          originalBytes,
        );

        expect(derivatives.width, 6000);
        expect(derivatives.height, 8000);

        final decodedThumbnail = img.decodeImage(derivatives.thumbnailBytes);
        expect(decodedThumbnail, isNotNull);
        expect(decodedThumbnail!.width, lessThanOrEqualTo(500));
        expect(decodedThumbnail.height, lessThanOrEqualTo(500));
      },
    );

    test('preserves aspect ratio when capping the thumbnail', () async {
      final originalBytes = _syntheticJpeg(4000, 2000);

      final derivatives = await ThumbnailService.createDerivatives(
        originalBytes,
      );

      final decodedThumbnail = img.decodeImage(derivatives.thumbnailBytes);
      expect(decodedThumbnail, isNotNull);
      expect(decodedThumbnail!.width, 500);
      expect(decodedThumbnail.height, 250);
    });

    test(
      'never upscales an image already smaller than the thumbnail cap',
      () async {
        final originalBytes = _syntheticJpeg(320, 240);

        final derivatives = await ThumbnailService.createDerivatives(
          originalBytes,
        );

        expect(derivatives.width, 320);
        expect(derivatives.height, 240);

        final decodedThumbnail = img.decodeImage(derivatives.thumbnailBytes);
        expect(decodedThumbnail, isNotNull);
        expect(decodedThumbnail!.width, 320);
        expect(decodedThumbnail.height, 240);
      },
    );
  });
}
