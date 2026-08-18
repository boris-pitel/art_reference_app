import 'dart:typed_data';

import 'package:image/image.dart' as img;

// Mirrors lib/services/photo_metadata_service.dart, reimplemented here
// without the package:flutter/foundation.dart dependency so this admin
// console stays a plain Dart executable.
const _tagDateTimeOriginal = 0x9003;
const _tagDateTime = 0x0132;
const _tagExposureTime = 0x829A;
const _tagFNumber = 0x829D;
const _tagIsoSpeed = 0x8827;
const _tagFocalLength = 0x920A;
const _tagLensModel = 0xA434;

final _controlCharacters = RegExp(r'[\x00-\x1F\x7F]');

class DecodedImageInfo {
  const DecodedImageInfo({
    required this.width,
    required this.height,
    required this.captureTimestamp,
    required this.photoMetadata,
  });

  final int width;
  final int height;
  final DateTime? captureTimestamp;
  final Map<String, dynamic>? photoMetadata;
}

/// Decodes an already-stored image (always a plain JPEG/PNG by the time it
/// reaches Storage, even for originally-HEIC uploads) to recover its pixel
/// dimensions and, when present, its EXIF fields. Returns null if the bytes
/// can't be decoded at all.
DecodedImageInfo? decodeImageInfo(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  DateTime? captureTimestamp;
  Map<String, dynamic>? photoMetadata;

  if (decoded.hasExif) {
    final exif = decoded.exif;

    captureTimestamp =
        _parseExifDateTime(exif.exifIfd[_tagDateTimeOriginal]?.toString()) ??
        _parseExifDateTime(exif.imageIfd[_tagDateTime]?.toString());

    final metadata = <String, dynamic>{
      if (_nullIfEmpty(exif.imageIfd.make) != null)
        'camera_make': _nullIfEmpty(exif.imageIfd.make),
      if (_nullIfEmpty(exif.imageIfd.model) != null)
        'camera_model': _nullIfEmpty(exif.imageIfd.model),
      if (_nullIfEmpty(exif.exifIfd[_tagLensModel]?.toString()) != null)
        'lens_model': _nullIfEmpty(exif.exifIfd[_tagLensModel]?.toString()),
      if (_positiveOrNull(exif.exifIfd[_tagFNumber]?.toDouble()) != null)
        'aperture': _positiveOrNull(exif.exifIfd[_tagFNumber]?.toDouble()),
      if (_formatShutterSpeed(exif.exifIfd[_tagExposureTime]) != null)
        'shutter_speed': _formatShutterSpeed(exif.exifIfd[_tagExposureTime]),
      if (_positiveIntOrNull(exif.exifIfd[_tagIsoSpeed]?.toInt()) != null)
        'iso': _positiveIntOrNull(exif.exifIfd[_tagIsoSpeed]?.toInt()),
      if (_positiveOrNull(exif.exifIfd[_tagFocalLength]?.toDouble()) != null)
        'focal_length_mm': _positiveOrNull(
          exif.exifIfd[_tagFocalLength]?.toDouble(),
        ),
    };

    if (metadata.isNotEmpty) {
      photoMetadata = metadata;
    }
  }

  return DecodedImageInfo(
    width: decoded.width,
    height: decoded.height,
    captureTimestamp: captureTimestamp,
    photoMetadata: photoMetadata,
  );
}

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final cleaned = value.replaceAll(_controlCharacters, '').trim();
  return cleaned.isEmpty ? null : cleaned;
}

double? _positiveOrNull(double? value) =>
    (value != null && value > 0) ? value : null;

int? _positiveIntOrNull(int? value) => (value != null && value > 0) ? value : null;

DateTime? _parseExifDateTime(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

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

String? _formatShutterSpeed(img.IfdValue? exposureTimeValue) {
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

class BackfillResult {
  const BackfillResult({
    required this.total,
    required this.updated,
    required this.skipped,
    required this.failed,
  });

  final int total;
  final int updated;
  final int skipped;
  final int failed;
}

/// Re-encodes a stored original (always plain JPEG/PNG by the time it's in
/// Storage, even for originally-HEIC uploads) into a display-resolution
/// JPEG, mirroring lib/services/thumbnail_service_native.dart's derivative
/// generation. Never upscales — an image already smaller than the cap is
/// just re-encoded as-is. Returns null if the bytes can't be decoded.
Uint8List? generateDisplayJpeg(
  Uint8List originalBytes, {
  int maxDimension = 3072,
  int quality = 88,
}) {
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) return null;

  final corrected = img.bakeOrientation(decoded);

  final needsDownscale =
      corrected.width > maxDimension || corrected.height > maxDimension;
  final source = needsDownscale
      ? img.copyResize(
          corrected,
          width: corrected.width >= corrected.height ? maxDimension : null,
          height: corrected.height > corrected.width ? maxDimension : null,
          interpolation: img.Interpolation.average,
        )
      : corrected;

  return Uint8List.fromList(img.encodeJpg(source, quality: quality));
}
