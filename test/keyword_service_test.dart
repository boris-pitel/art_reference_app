import 'package:art_reference_app/services/keyword_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageKeyword.fromJson', () {
    test('parses and trims a keyword record', () {
      final keyword = ImageKeyword.fromJson({
        'id': 7,
        'image_id': ' image-id ',
        'keyword': ' warm light ',
        'date_added': '2026-08-12T10:30:00Z',
      });

      expect(keyword.id, 7);
      expect(keyword.imageId, 'image-id');
      expect(keyword.keyword, 'warm light');
      expect(keyword.dateAdded.isUtc, isTrue);
    });

    test('rejects incomplete records', () {
      for (final row in [
        {
          'id': '7',
          'image_id': 'image-id',
          'keyword': 'light',
          'date_added': '2026-08-12T10:30:00Z',
        },
        {
          'id': 7,
          'image_id': ' ',
          'keyword': 'light',
          'date_added': '2026-08-12T10:30:00Z',
        },
        {
          'id': 7,
          'image_id': 'image-id',
          'keyword': ' ',
          'date_added': '2026-08-12T10:30:00Z',
        },
      ]) {
        expect(() => ImageKeyword.fromJson(row), throwsStateError);
      }
    });
  });

  group('KeywordService.normalizeKeyword', () {
    test('trims and collapses internal whitespace', () {
      expect(
        KeywordService.normalizeKeyword('  warm\n  afternoon\tlight  '),
        'warm afternoon light',
      );
    });

    test('rejects empty keywords', () {
      expect(
        () => KeywordService.normalizeKeyword(' \n\t '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('enforces the 100-character limit', () {
      expect(KeywordService.normalizeKeyword('a' * 100), hasLength(100));
      expect(
        () => KeywordService.normalizeKeyword('a' * 101),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  test('DuplicateKeywordException identifies the duplicate', () {
    expect(
      const DuplicateKeywordException('portrait').toString(),
      contains('portrait'),
    );
  });
}
