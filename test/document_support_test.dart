import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_io.dart';
import 'package:art_reference_app/models/reference_document.dart';
import 'package:art_reference_app/services/document_file_cache.dart';
import 'package:art_reference_app/services/document_text.dart';
import 'package:art_reference_app/services/rtf_text.dart';

void main() {
  test(
    'accepts supported document types, rejects empty, oversized and other files',
    () {
      for (final type in ['PDF', 'txt', 'rtf', 'doc', 'docx']) {
        expect(DocumentFormat.validate('study.$type', 10), type.toLowerCase());
      }
      expect(
        () => DocumentFormat.validate('study.exe', 10),
        throwsFormatException,
      );
      expect(
        () => DocumentFormat.validate('study.pdf', 0),
        throwsFormatException,
      );
      expect(
        () => DocumentFormat.validate('study.pdf', DocumentFormat.maxBytes + 1),
        throwsFormatException,
      );
    },
  );
  test(
    'RTF restores nested formatting and hides metadata and embedded objects',
    () {
      final spans = rtfText(
        Uint8List.fromList(
          latin1.encode(
            r'{\rtf1{\fonttbl Hidden font}{\*\info secret}Normal {\b Bold {\i both} bold} normal\par\bullet\tab item{\pict abcdef}}',
          ),
        ),
      );
      expect(
        spans.map((s) => s.text).join(),
        'Normal Bold both bold normal\n•\titem',
      );
      expect(
        spans.singleWhere((s) => s.text == 'both').style?.fontStyle,
        FontStyle.italic,
      );
      expect(
        spans.singleWhere((s) => s.text == 'both').style?.fontWeight,
        FontWeight.bold,
      );
      expect(spans.last.style?.fontWeight, FontWeight.normal);
    },
  );
  test('RTF decodes Unicode fallback and escaped delimiters', () {
    final spans = rtfText(
      Uint8List.fromList(latin1.encode(r'{\rtf1\uc1 caf\u233? \{text\} \\}')),
    );
    expect(spans.map((s) => s.text).join(), 'café {text} \\');
  });
  test('large RTF text stays a single formatting run', () {
    final text = List.filled(100000, 'a').join();
    final spans = rtfText(Uint8List.fromList(latin1.encode('{\\rtf1 $text}')));
    expect(spans.length, 1);
    expect(spans.single.text, text);
  });
  test('text viewer decodes UTF8 and UTF16 byte order marks', () {
    expect(
      documentText(
        Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('hello')]),
      ),
      'hello',
    );
    expect(
      documentText(Uint8List.fromList([0xff, 0xfe, 65, 0, 0xe9, 0])),
      'Aé',
    );
    expect(
      documentText(Uint8List.fromList([0xfe, 0xff, 0, 65, 0, 0xe9])),
      'Aé',
    );
  });
  test('offline files persist and cannot be read by another account', () async {
    final factory = idbFactoryMemory;
    final cache = DocumentFileCache(factory: factory);
    await cache.write('alice', 'doc-1', Uint8List.fromList([1, 2, 3]));
    expect(await DocumentFileCache(factory: factory).read('alice', 'doc-1'), [
      1,
      2,
      3,
    ]);
    expect(await cache.read('bob', 'doc-1'), isNull);
    await cache.remove('bob', 'doc-1');
    expect(await cache.read('alice', 'doc-1'), [1, 2, 3]);
    await cache.remove('alice', 'doc-1');
    expect(await cache.read('alice', 'doc-1'), isNull);
    await cache.write('alice', 'doc-2', Uint8List.fromList([4]));
    await cache.write('alice', 'doc-2-thumbnail', Uint8List.fromList([5]));
    await cache.write('bob', 'doc-2', Uint8List.fromList([6]));
    await cache.clearUser('alice');
    expect(await cache.read('alice', 'doc-2'), isNull);
    expect(await cache.read('alice', 'doc-2-thumbnail'), isNull);
    expect(await cache.read('bob', 'doc-2'), [6]);
  });
}
