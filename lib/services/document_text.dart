import 'dart:convert';
import 'dart:typed_data';

String documentText(Uint8List bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    final little = bytes[0] == 0xff;
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(
        little
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }
  return utf8
      .decode(bytes, allowMalformed: true)
      .replaceFirst(RegExp('^\uFEFF'), '');
}
