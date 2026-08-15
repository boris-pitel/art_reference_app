import 'dart:typed_data';

import 'package:image/image.dart' as img;

// Raw EXIF tag IDs used below (not all of them have named getters on
// package:image's IfdDirectory).
const _tagDateTimeOriginal = 0x9003;
const _tagDateTime = 0x0132;
const _tagExposureTime = 0x829A;
const _tagFNumber = 0x829D;
const _tagIsoSpeed = 0x8827;
const _tagFocalLength = 0x920A;
const _tagLensModel = 0xA434;

class PhotoMetadata {
  const PhotoMetadata({
    this.cameraMake,
    this.cameraModel,
    this.lensModel,
    this.aperture,
    this.shutterSpeed,
    this.iso,
    this.focalLengthMm,
  });

  final String? cameraMake;
  final String? cameraModel;
  final String? lensModel;
  final double? aperture;
  final String? shutterSpeed;
  final int? iso;
  final double? focalLengthMm;

  bool get isEmpty =>
      cameraMake == null &&
      cameraModel == null &&
      lensModel == null &&
      aperture == null &&
      shutterSpeed == null &&
      iso == null &&
      focalLengthMm == null;

  Map<String, dynamic> toJson() {
    return {
      if (cameraMake != null) 'camera_make': cameraMake,
      if (cameraModel != null) 'camera_model': cameraModel,
      if (lensModel != null) 'lens_model': lensModel,
      if (aperture != null) 'aperture': aperture,
      if (shutterSpeed != null) 'shutter_speed': shutterSpeed,
      if (iso != null) 'iso': iso,
      if (focalLengthMm != null) 'focal_length_mm': focalLengthMm,
    };
  }

  factory PhotoMetadata.fromJson(Map<String, dynamic> json) {
    return PhotoMetadata(
      cameraMake: json['camera_make'] as String?,
      cameraModel: json['camera_model'] as String?,
      lensModel: json['lens_model'] as String?,
      aperture: (json['aperture'] as num?)?.toDouble(),
      shutterSpeed: json['shutter_speed'] as String?,
      iso: (json['iso'] as num?)?.toInt(),
      focalLengthMm: (json['focal_length_mm'] as num?)?.toDouble(),
    );
  }
}

class PhotoMetadataExtraction {
  const PhotoMetadataExtraction({this.captureTimestamp, this.metadata});

  final DateTime? captureTimestamp;
  final PhotoMetadata? metadata;
}

/// Reads capture timestamp and camera/exposure EXIF fields out of an image,
/// when present. Never throws — a corrupt or missing EXIF segment just
/// results in an extraction with everything null.
class PhotoMetadataService {
  const PhotoMetadataService._();

  static PhotoMetadataExtraction extract(Uint8List imageBytes) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null || !decoded.hasExif) {
        return const PhotoMetadataExtraction();
      }

      final exif = decoded.exif;
      final captureTimestamp =
          _parseExifDateTime(exif.exifIfd[_tagDateTimeOriginal]?.toString()) ??
          _parseExifDateTime(exif.imageIfd[_tagDateTime]?.toString());

      final metadata = PhotoMetadata(
        cameraMake: _nullIfEmpty(exif.imageIfd.make),
        cameraModel: _nullIfEmpty(exif.imageIfd.model),
        lensModel: _nullIfEmpty(exif.exifIfd[_tagLensModel]?.toString()),
        aperture: _positiveOrNull(exif.exifIfd[_tagFNumber]?.toDouble()),
        shutterSpeed: _formatShutterSpeed(exif.exifIfd[_tagExposureTime]),
        iso: _positiveIntOrNull(exif.exifIfd[_tagIsoSpeed]?.toInt()),
        focalLengthMm: _positiveOrNull(
          exif.exifIfd[_tagFocalLength]?.toDouble(),
        ),
      );

      return PhotoMetadataExtraction(
        captureTimestamp: captureTimestamp,
        metadata: metadata.isEmpty ? null : metadata,
      );
    } catch (_) {
      return const PhotoMetadataExtraction();
    }
  }

  static String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static double? _positiveOrNull(double? value) =>
      (value != null && value > 0) ? value : null;

  static int? _positiveIntOrNull(int? value) =>
      (value != null && value > 0) ? value : null;

  static DateTime? _parseExifDateTime(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    // EXIF timestamps look like "YYYY:MM:DD HH:MM:SS".
    final match = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(trimmed);
    if (match == null) return null;

    try {
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _formatShutterSpeed(img.IfdValue? exposureTimeValue) {
    if (exposureTimeValue == null) return null;

    final seconds = exposureTimeValue.toDouble();
    if (seconds <= 0) return null;

    if (seconds >= 1) {
      final rounded = (seconds * 10).round() / 10;
      return rounded == rounded.roundToDouble()
          ? '${rounded.toInt()}s'
          : '${rounded}s';
    }

    final denominator = (1 / seconds).round();
    return denominator > 0 ? '1/${denominator}s' : null;
  }
}
