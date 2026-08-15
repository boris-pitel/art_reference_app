import 'dart:convert';
import 'dart:typed_data';

import 'package:art_reference_app/services/photo_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _tagDateTimeOriginal = 0x9003;
const _tagExposureTime = 0x829A;
const _tagFNumber = 0x829D;
const _tagIsoSpeed = 0x8827;
const _tagFocalLength = 0x920A;
const _tagLensModel = 0xA434;

void main() {
  group('PhotoMetadataService', () {
    test('returns an empty extraction for an image with no EXIF data', () {
      final image = img.Image(width: 10, height: 10);
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = PhotoMetadataService.extract(bytes);

      expect(result.captureTimestamp, isNull);
      expect(result.metadata, isNull);
    });

    test('extracts capture timestamp and camera/exposure fields from EXIF', () {
      final image = img.Image(width: 10, height: 10);
      image.exif.imageIfd.make = 'Canon';
      image.exif.imageIfd.model = 'EOS R5';
      image.exif.exifIfd[_tagDateTimeOriginal] = img.IfdValueAscii(
        '2024:06:15 14:30:00',
      );
      image.exif.exifIfd[_tagFNumber] = img.IfdValueRational(28, 10);
      image.exif.exifIfd[_tagExposureTime] = img.IfdValueRational(1, 125);
      image.exif.exifIfd[_tagIsoSpeed] = img.IfdValueLong(400);
      image.exif.exifIfd[_tagFocalLength] = img.IfdValueRational(50, 1);
      image.exif.exifIfd[_tagLensModel] = img.IfdValueAscii('RF50mm F1.2L');

      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = PhotoMetadataService.extract(bytes);

      expect(result.captureTimestamp, DateTime(2024, 6, 15, 14, 30, 0));

      final metadata = result.metadata;
      expect(metadata, isNotNull);
      expect(metadata!.cameraMake, 'Canon');
      expect(metadata.cameraModel, 'EOS R5');
      expect(metadata.lensModel, 'RF50mm F1.2L');
      expect(metadata.aperture, closeTo(2.8, 0.01));
      expect(metadata.shutterSpeed, '1/125s');
      expect(metadata.iso, 400);
      expect(metadata.focalLengthMm, 50.0);
    });

    test('round-trips through toJson/fromJson', () {
      const metadata = PhotoMetadata(
        cameraMake: 'Nikon',
        cameraModel: 'Z9',
        lensModel: '24-70mm',
        aperture: 4.0,
        shutterSpeed: '1/500s',
        iso: 800,
        focalLengthMm: 35.0,
      );

      final roundTripped = PhotoMetadata.fromJson(metadata.toJson());

      expect(roundTripped.cameraMake, metadata.cameraMake);
      expect(roundTripped.cameraModel, metadata.cameraModel);
      expect(roundTripped.lensModel, metadata.lensModel);
      expect(roundTripped.aperture, metadata.aperture);
      expect(roundTripped.shutterSpeed, metadata.shutterSpeed);
      expect(roundTripped.iso, metadata.iso);
      expect(roundTripped.focalLengthMm, metadata.focalLengthMm);
    });

    test('an all-null PhotoMetadata reports itself as empty', () {
      expect(const PhotoMetadata().isEmpty, isTrue);
      expect(const PhotoMetadata(iso: 100).isEmpty, isFalse);
    });

    test(
      'strips null-byte padding from EXIF strings so they never reach '
      'JSON/Postgres, which hard-rejects an embedded null escape',
      () {
        final image = img.Image(width: 10, height: 10);
        // Real cameras store Make/Model/LensModel as fixed-length,
        // null-padded ASCII per the TIFF spec.
        image.exif.imageIfd.make = 'Canon\x00\x00\x00';
        image.exif.imageIfd.model = 'EOS R5\x00';
        image.exif.exifIfd[_tagLensModel] = img.IfdValueAscii(
          'RF50mm\x00F1.2L USM\x00',
        );

        final bytes = Uint8List.fromList(img.encodeJpg(image));
        final metadata = PhotoMetadataService.extract(bytes).metadata;

        expect(metadata, isNotNull);
        expect(metadata!.cameraMake, 'Canon');
        expect(metadata.cameraModel, 'EOS R5');
        // An embedded (not just trailing) null is also stripped, not just
        // truncated at the first one.
        expect(metadata.lensModel, 'RF50mmF1.2L USM');
        for (final value in [
          metadata.cameraMake,
          metadata.cameraModel,
          metadata.lensModel,
        ]) {
          expect(value!.contains('\x00'), isFalse);
          // This is the exact escape sequence Postgres's jsonb type
          // rejects with "unsupported Unicode escape sequence" - confirm
          // it can never appear in the JSON-encoded output.
          expect(jsonEncode(value).contains('\\u0000'), isFalse);
        }
      },
    );

    test(
      'EXIF survives a resize + re-encode, so extracting from a '
      'thumbnail (as image_asset_service does on native, to avoid '
      'decoding a full-resolution camera photo twice) still works',
      () {
        final original = img.Image(width: 4000, height: 3000);
        original.exif.imageIfd.make = 'Sony';
        original.exif.imageIfd.model = 'A7R V';
        original.exif.exifIfd[_tagDateTimeOriginal] = img.IfdValueAscii(
          '2025:01:20 08:00:00',
        );
        original.exif.exifIfd[_tagFNumber] = img.IfdValueRational(18, 10);
        original.exif.exifIfd[_tagIsoSpeed] = img.IfdValueLong(100);

        final thumbnail = img.copyResize(original, width: 500);
        final thumbnailBytes = Uint8List.fromList(
          img.encodeJpg(thumbnail, quality: 80),
        );

        final result = PhotoMetadataService.extract(thumbnailBytes);

        expect(result.captureTimestamp, DateTime(2025, 1, 20, 8, 0, 0));
        expect(result.metadata?.cameraMake, 'Sony');
        expect(result.metadata?.cameraModel, 'A7R V');
        expect(result.metadata?.aperture, closeTo(1.8, 0.01));
        expect(result.metadata?.iso, 100);
      },
    );
  });
}
