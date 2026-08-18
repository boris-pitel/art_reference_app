import 'dart:typed_data';

import 'package:art_reference_app/services/image_dimensions_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _jpeg(int width, int height) {
  return Uint8List.fromList(
    img.encodeJpg(img.Image(width: width, height: height), quality: 80),
  );
}

Uint8List _png(int width, int height) {
  return Uint8List.fromList(img.encodePng(img.Image(width: width, height: height)));
}

void main() {
  group('ImageDimensionsReader', () {
    test('reads JPEG dimensions without decoding the image', () {
      final result = ImageDimensionsReader.read(_jpeg(640, 480));

      expect(result, isNotNull);
      expect(result!.width, 640);
      expect(result.height, 480);
    });

    test('reads portrait JPEG dimensions in the right order', () {
      // Width and height sit adjacent in the SOF marker and are easy to
      // transpose, which a square test image would never catch.
      final result = ImageDimensionsReader.read(_jpeg(480, 640));

      expect(result!.width, 480);
      expect(result.height, 640);
    });

    test('reads PNG dimensions', () {
      final result = ImageDimensionsReader.read(_png(320, 200));

      expect(result, isNotNull);
      expect(result!.width, 320);
      expect(result.height, 200);
    });

    test('reports megapixels for the size that fails on iOS', () {
      // The photo that never reached Photos: 48MP, against a 32MP ceiling.
      final result = ImageDimensionsReader.read(_jpeg(6000, 8000));

      expect(result!.megapixels, 48);
      expect(result.megapixels, greaterThan(32));
    });

    test('a large-but-allowed image stays under the limit', () {
      // 4000x6000 is 24MP — a big camera photo that should not be warned about.
      final result = ImageDimensionsReader.read(_jpeg(4000, 6000));

      expect(result!.megapixels, 24);
      expect(result.megapixels, lessThanOrEqualTo(32));
    });

    test('returns null rather than guessing for non-image bytes', () {
      expect(ImageDimensionsReader.read(Uint8List(0)), isNull);
      expect(
        ImageDimensionsReader.read(Uint8List.fromList([1, 2, 3, 4, 5])),
        isNull,
      );
      expect(
        ImageDimensionsReader.read(
          Uint8List.fromList('not an image at all'.codeUnits),
        ),
        isNull,
      );
    });

    test('survives a truncated JPEG header', () {
      final truncated = Uint8List.sublistView(_jpeg(640, 480), 0, 8);

      expect(() => ImageDimensionsReader.read(truncated), returnsNormally);
    });
  });
}
