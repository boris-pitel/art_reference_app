import 'dart:typed_data';

/// Locates and extracts the raw EXIF/TIFF payload embedded in a HEIF/HEIC
/// container (ISO/IEC 23008-12), reading directly from the *original* file
/// bytes rather than the JPEG produced by HEIC-to-JPEG conversion.
///
/// HEIC is the default capture format on iPhones, and stores EXIF as a
/// distinct metadata item inside the ISOBMFF box structure — not inline in
/// a JPEG-style APPn segment the way package:image expects. Neither
/// package:image (no HEIC decoder) nor this app's platform HEIC-to-JPEG
/// converter (which only bakes in orientation, discarding the rest of the
/// EXIF via a plain pixel-only Bitmap re-encode on Android) preserve it, so
/// this has to be pulled out before that lossy conversion happens.
class HeifExifReader {
  const HeifExifReader._();

  /// Returns the raw TIFF/EXIF bytes (starting at the "II"/"MM" header), or
  /// null if no Exif item could be located. Never throws — a malformed,
  /// truncated, or unsupported container just results in null, same as a
  /// photo with no EXIF at all.
  static Uint8List? findExifPayload(Uint8List bytes) {
    try {
      final meta = _findBox(bytes, 0, bytes.length, 'meta');
      if (meta == null) return null;

      // `meta` is a full box: 4 bytes of version/flags precede its children.
      final childrenStart = meta.payloadStart + 4;
      if (childrenStart > meta.payloadEnd) return null;

      final iinf = _findBox(bytes, childrenStart, meta.payloadEnd, 'iinf');
      final iloc = _findBox(bytes, childrenStart, meta.payloadEnd, 'iloc');
      if (iinf == null || iloc == null) return null;

      final exifItemId = _findExifItemId(bytes, iinf);
      if (exifItemId == null) return null;

      final extent = _findItemExtent(bytes, iloc, exifItemId);
      if (extent == null) return null;

      final (offset, length) = extent;
      if (offset < 0 || length < 4 || offset + length > bytes.length) {
        return null;
      }

      // Per the HEIF spec, an Exif item's payload starts with a 4-byte
      // big-endian offset (almost always 0) from just after this field to
      // the actual TIFF header.
      final headerOffset = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0, Endian.big);
      final tiffStart = offset + 4 + headerOffset;
      if (tiffStart < offset + 4 || tiffStart >= offset + length) {
        return null;
      }

      return bytes.sublist(tiffStart, offset + length);
    } catch (_) {
      return null;
    }
  }

  // --- ISOBMFF box walking --------------------------------------------

  static _Box? _findBox(Uint8List bytes, int start, int end, String type) {
    var pos = start;
    while (pos + 8 <= end) {
      var size = ByteData.sublistView(
        bytes,
        pos,
        pos + 4,
      ).getUint32(0, Endian.big);
      final boxType = String.fromCharCodes(bytes, pos + 4, pos + 8);
      var headerSize = 8;

      if (size == 1) {
        if (pos + 16 > end) return null;
        size = ByteData.sublistView(
          bytes,
          pos + 8,
          pos + 16,
        ).getUint64(0, Endian.big);
        headerSize = 16;
      } else if (size == 0) {
        size = end - pos;
      }

      if (size < headerSize || pos + size > end) return null;

      if (boxType == type) {
        return _Box(payloadStart: pos + headerSize, payloadEnd: pos + size);
      }

      pos += size;
    }
    return null;
  }

  /// `iinf` is a full box whose children are `infe` (item info entry)
  /// boxes; returns the item_ID of the first one whose item_type is "Exif".
  static int? _findExifItemId(Uint8List bytes, _Box iinf) {
    if (iinf.payloadStart + 4 > iinf.payloadEnd) return null;

    final version = bytes[iinf.payloadStart];
    final entryCountFieldSize = version == 0 ? 2 : 4;
    var pos = iinf.payloadStart + 4 + entryCountFieldSize;

    while (pos + 8 <= iinf.payloadEnd) {
      var size = ByteData.sublistView(
        bytes,
        pos,
        pos + 4,
      ).getUint32(0, Endian.big);
      final boxType = String.fromCharCodes(bytes, pos + 4, pos + 8);
      var headerSize = 8;

      if (size == 1) {
        if (pos + 16 > iinf.payloadEnd) return null;
        size = ByteData.sublistView(
          bytes,
          pos + 8,
          pos + 16,
        ).getUint64(0, Endian.big);
        headerSize = 16;
      } else if (size == 0) {
        size = iinf.payloadEnd - pos;
      }

      if (size < headerSize || pos + size > iinf.payloadEnd) return null;

      if (boxType == 'infe') {
        final id = _exifItemIdFromInfe(bytes, pos + headerSize, pos + size);
        if (id != null) return id;
      }

      pos += size;
    }
    return null;
  }

  static int? _exifItemIdFromInfe(Uint8List bytes, int start, int end) {
    if (start + 4 > end) return null;

    final infeVersion = bytes[start];
    // item_type (and therefore the ability to spot "Exif") only exists
    // from version 2 onward; earlier versions aren't used by modern HEIC
    // encoders for this purpose.
    if (infeVersion < 2) return null;

    final idSize = infeVersion == 2 ? 2 : 4;
    final idStart = start + 4;
    final typeStart = idStart + idSize + 2; // + item_protection_index
    if (typeStart + 4 > end) return null;

    final itemType = String.fromCharCodes(bytes, typeStart, typeStart + 4);
    if (itemType != 'Exif') return null;

    return idSize == 2
        ? ByteData.sublistView(
            bytes,
            idStart,
            idStart + 2,
          ).getUint16(0, Endian.big)
        : ByteData.sublistView(
            bytes,
            idStart,
            idStart + 4,
          ).getUint32(0, Endian.big);
  }

  /// `iloc` maps item IDs to a (file offset, length) extent. Only
  /// construction_method 0 (plain file offsets, what Apple's HEIC encoder
  /// uses) is supported; anything else is treated as not found rather than
  /// risking reading the wrong bytes.
  static (int, int)? _findItemExtent(Uint8List bytes, _Box iloc, int itemId) {
    var pos = iloc.payloadStart;
    if (pos + 4 > iloc.payloadEnd) return null;

    final version = bytes[pos];
    pos += 4; // version + flags

    if (pos + 2 > iloc.payloadEnd) return null;
    final offsetSize = bytes[pos] >> 4;
    final lengthSize = bytes[pos] & 0xF;
    final baseOffsetSize = bytes[pos + 1] >> 4;
    final indexSize = bytes[pos + 1] & 0xF;
    pos += 2;

    final itemIdSize = version < 2 ? 2 : 4;
    final itemCountSize = version < 2 ? 2 : 4;
    if (pos + itemCountSize > iloc.payloadEnd) return null;
    final itemCount = itemCountSize == 2
        ? ByteData.sublistView(bytes, pos, pos + 2).getUint16(0, Endian.big)
        : ByteData.sublistView(bytes, pos, pos + 4).getUint32(0, Endian.big);
    pos += itemCountSize;

    for (var i = 0; i < itemCount; i++) {
      if (pos + itemIdSize > iloc.payloadEnd) return null;
      final currentItemId = itemIdSize == 2
          ? ByteData.sublistView(
              bytes,
              pos,
              pos + 2,
            ).getUint16(0, Endian.big)
          : ByteData.sublistView(
              bytes,
              pos,
              pos + 4,
            ).getUint32(0, Endian.big);
      pos += itemIdSize;

      var constructionMethod = 0;
      if (version == 1 || version == 2) {
        if (pos + 2 > iloc.payloadEnd) return null;
        constructionMethod =
            ByteData.sublistView(
              bytes,
              pos,
              pos + 2,
            ).getUint16(0, Endian.big) &
            0xF;
        pos += 2;
      }

      pos += 2; // data_reference_index
      if (pos + baseOffsetSize > iloc.payloadEnd) return null;
      final baseOffset = _readUint(bytes, pos, baseOffsetSize);
      pos += baseOffsetSize;

      if (pos + 2 > iloc.payloadEnd) return null;
      final extentCount = ByteData.sublistView(
        bytes,
        pos,
        pos + 2,
      ).getUint16(0, Endian.big);
      pos += 2;

      int? firstExtentOffset;
      var totalLength = 0;
      for (var e = 0; e < extentCount; e++) {
        if (version == 1 || version == 2) {
          pos += indexSize;
        }
        if (pos + offsetSize + lengthSize > iloc.payloadEnd) return null;
        final extentOffset = _readUint(bytes, pos, offsetSize);
        pos += offsetSize;
        final extentLength = _readUint(bytes, pos, lengthSize);
        pos += lengthSize;
        firstExtentOffset ??= extentOffset;
        totalLength += extentLength;
      }

      if (currentItemId == itemId &&
          constructionMethod == 0 &&
          firstExtentOffset != null) {
        return (baseOffset + firstExtentOffset, totalLength);
      }
    }
    return null;
  }

  static int _readUint(Uint8List bytes, int offset, int size) {
    if (size == 0) return 0;
    var value = 0;
    for (var i = 0; i < size; i++) {
      value = (value << 8) | bytes[offset + i];
    }
    return value;
  }
}

class _Box {
  const _Box({required this.payloadStart, required this.payloadEnd});
  final int payloadStart;
  final int payloadEnd;

  @override
  String toString() => '_Box($payloadStart..$payloadEnd)';
}
