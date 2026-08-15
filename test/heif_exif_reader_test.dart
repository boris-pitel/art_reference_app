import 'dart:typed_data';

import 'package:art_reference_app/services/heif_exif_reader.dart';
import 'package:art_reference_app/services/photo_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _box(String type, List<int> payload) {
  final builder = BytesBuilder();
  final header = ByteData(4);
  header.setUint32(0, payload.length + 8, Endian.big);
  builder.add(header.buffer.asUint8List());
  builder.add(type.codeUnits);
  builder.add(payload);
  return builder.toBytes();
}

/// Builds a minimal-but-spec-accurate HEIC container with a single "Exif"
/// item, so HeifExifReader can be exercised against real ISOBMFF box
/// bytes rather than just unit-testing its pieces in isolation.
Uint8List _buildSyntheticHeic(Uint8List tiffBytes) {
  final ftyp = _box('ftyp', [
    ...'heic'.codeUnits,
    0, 0, 0, 0, // minor version
    ...'heic'.codeUnits,
    ...'mif1'.codeUnits,
  ]);

  // infe (full box, version 2): version/flags, item_ID=1,
  // item_protection_index=0, item_type="Exif", item_name="\0".
  final infePayload = [
    2, 0, 0, 0, // version 2, flags 0
    0, 1, // item_ID = 1
    0, 0, // item_protection_index
    ...'Exif'.codeUnits,
    0, // item_name (empty, null-terminated)
  ];
  final infe = _box('infe', infePayload);

  // iinf (full box, version 0): version/flags, entry_count(2)=1, [infe].
  final iinfPayload = [0, 0, 0, 0, 0, 1, ...infe];
  final iinf = _box('iinf', iinfPayload);

  // iloc (full box, version 0) with a placeholder extent_offset that gets
  // patched once the real absolute offset is known.
  final ilocPayload = <int>[
    0, 0, 0, 0, // version 0, flags 0
    0x44, 0x00, // offset_size=4, length_size=4 | base_offset_size=0, index_size=0
    0, 1, // item_count = 1
    0, 1, // item_ID = 1
    0, 0, // data_reference_index
    // (base_offset omitted: base_offset_size == 0)
    0, 1, // extent_count = 1
    0, 0, 0, 0, // extent_offset — patched below
    0, 0, 0, 0, // extent_length — patched below
  ];
  final iloc = _box('iloc', ilocPayload);

  final metaPayload = [0, 0, 0, 0, ...iinf, ...iloc];
  final meta = _box('meta', metaPayload);

  final exifItemPayload = [
    0, 0, 0, 0, // exif_tiff_header_offset = 0
    ...tiffBytes,
  ];

  final container = BytesBuilder()
    ..add(ftyp)
    ..add(meta);
  final exifItemOffset = container.length;
  container.add(exifItemPayload);

  final bytes = container.toBytes();

  // Patch iloc's extent_offset/extent_length now that the real absolute
  // file offset of the exif item is known. iloc's payload ends with:
  // [... extent_offset(4) extent_length(4)] — locate it by searching for
  // the 'iloc' box within the already-built bytes (test-only convenience;
  // production parsing never needs to locate its own patch point).
  final ilocTag = 'iloc'.codeUnits;
  var ilocStart = -1;
  for (var i = 0; i + 4 <= bytes.length; i++) {
    if (bytes[i] == ilocTag[0] &&
        bytes[i + 1] == ilocTag[1] &&
        bytes[i + 2] == ilocTag[2] &&
        bytes[i + 3] == ilocTag[3]) {
      ilocStart = i;
      break;
    }
  }
  if (ilocStart < 0) throw StateError('iloc box not found while patching');
  final extentFieldsStart = ilocStart + 4 + ilocPayload.length - 8;
  final patch = ByteData.sublistView(bytes, extentFieldsStart, extentFieldsStart + 8);
  // extent_offset points at the start of the item payload — the 4-byte
  // exif_tiff_header_offset field, which the reader skips past itself —
  // and extent_length covers that field plus the TIFF bytes after it.
  patch.setUint32(0, exifItemOffset, Endian.big);
  patch.setUint32(4, 4 + tiffBytes.length, Endian.big);

  return bytes;
}

Uint8List _buildTiffBytes({
  required String make,
  required String model,
  required String dateTimeOriginal,
  required int fNumberNumerator,
  required int fNumberDenominator,
  required int isoSpeed,
}) {
  final exif = img.ExifData();
  exif.imageIfd.make = make;
  exif.imageIfd.model = model;
  exif.exifIfd[0x9003] = img.IfdValueAscii(dateTimeOriginal);
  exif.exifIfd[0x829D] = img.IfdValueRational(
    fNumberNumerator,
    fNumberDenominator,
  );
  exif.exifIfd[0x8827] = img.IfdValueLong(isoSpeed);

  final out = img.OutputBuffer();
  exif.write(out);
  return out.getBytes();
}

void main() {
  group('HeifExifReader', () {
    test('locates and extracts the Exif item from a synthetic HEIC file', () {
      final tiffBytes = _buildTiffBytes(
        make: 'Apple',
        model: 'iPhone 15 Pro',
        dateTimeOriginal: '2025:07:04 12:00:00',
        fNumberNumerator: 18,
        fNumberDenominator: 10,
        isoSpeed: 64,
      );
      final heic = _buildSyntheticHeic(tiffBytes);

      final extracted = HeifExifReader.findExifPayload(heic);

      expect(extracted, isNotNull);
      expect(extracted, tiffBytes);
    });

    test('returns null for a non-HEIC / unrelated byte blob', () {
      final random = Uint8List.fromList(List.generate(200, (i) => i % 256));
      expect(HeifExifReader.findExifPayload(random), isNull);
    });

    test('returns null for a HEIC-shaped file with no Exif item', () {
      final ftyp = _box('ftyp', [
        ...'heic'.codeUnits,
        0, 0, 0, 0,
        ...'heic'.codeUnits,
      ]);
      final iinf = _box('iinf', [0, 0, 0, 0, 0, 0]); // zero items
      final iloc = _box('iloc', [0, 0, 0, 0, 0x44, 0x00, 0, 0]);
      final meta = _box('meta', [0, 0, 0, 0, ...iinf, ...iloc]);
      final bytes = Uint8List.fromList([...ftyp, ...meta]);

      expect(HeifExifReader.findExifPayload(bytes), isNull);
    });
  });

  group('PhotoMetadataService.extractFromRawExif via HEIC container', () {
    test('end-to-end: HEIC bytes in, camera/exposure fields out', () {
      final tiffBytes = _buildTiffBytes(
        make: 'Apple',
        model: 'iPhone 14',
        dateTimeOriginal: '2024:12:25 09:30:00',
        fNumberNumerator: 22,
        fNumberDenominator: 10,
        isoSpeed: 125,
      );
      final heic = _buildSyntheticHeic(tiffBytes);

      final rawExif = HeifExifReader.findExifPayload(heic);
      expect(rawExif, isNotNull);

      final result = PhotoMetadataService.extractFromRawExif(rawExif!);

      expect(result.captureTimestamp, DateTime(2024, 12, 25, 9, 30, 0));
      expect(result.metadata?.cameraMake, 'Apple');
      expect(result.metadata?.cameraModel, 'iPhone 14');
      expect(result.metadata?.aperture, closeTo(2.2, 0.01));
      expect(result.metadata?.iso, 125);
    });
  });
}
