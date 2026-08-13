import 'package:art_reference_app/services/image_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageSearchResult.fromJson', () {
    test('normalizes optional text and match lists', () {
      final result = ImageSearchResult.fromJson({
        'id': ' image-id ',
        'date_added': '2026-08-12T10:30:00Z',
        'image_url': ' https://example.test/image ',
        'thumbnail_url': ' ',
        'title': ' Portrait study ',
        'notes': '',
        'matching_keywords': [' face ', '', 42, 'light'],
        'matched_in': [' title ', null],
      });

      expect(result.id, 'image-id');
      expect(result.imageUrl, 'https://example.test/image');
      expect(result.thumbnailUrl, isNull);
      expect(result.title, 'Portrait study');
      expect(result.notes, isNull);
      expect(result.matchingKeywords, ['face', 'light']);
      expect(result.matchedIn, ['title']);
    });

    test('rejects required fields with invalid types or values', () {
      for (final row in [
        {'id': '', 'date_added': '2026-08-12T10:30:00Z', 'image_url': 'url'},
        {'id': 'id', 'date_added': '', 'image_url': 'url'},
        {'id': 'id', 'date_added': '2026-08-12T10:30:00Z', 'image_url': 12},
      ]) {
        expect(() => ImageSearchResult.fromJson(row), throwsStateError);
      }
    });
  });

  group('ImageSearchService request rules', () {
    test('normalizes surrounding whitespace', () {
      expect(ImageSearchService.normalizeQuery('  portrait  '), 'portrait');
    });

    test('skips an empty general search but allows favorites', () {
      expect(
        ImageSearchService.shouldSkipSearch('', favoritesOnly: false),
        isTrue,
      );
      expect(
        ImageSearchService.shouldSkipSearch('', favoritesOnly: true),
        isFalse,
      );
      expect(
        ImageSearchService.shouldSkipSearch('portrait', favoritesOnly: false),
        isFalse,
      );
    });
  });

  group('ImageSearchService.parseSearchResults', () {
    test('parses valid result lists', () {
      final results = ImageSearchService.parseSearchResults([
        {'id': 'id', 'date_added': '2026-08-12T10:30:00Z', 'image_url': 'url'},
      ]);
      expect(results.single.id, 'id');
    });

    test('surfaces backend errors', () {
      expect(
        () => ImageSearchService.parseSearchResults({'error': 'Search failed'}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Search failed',
          ),
        ),
      );
    });

    test('rejects non-list and malformed list responses', () {
      expect(
        () => ImageSearchService.parseSearchResults(null),
        throwsStateError,
      );
      expect(
        () => ImageSearchService.parseSearchResults(['bad item']),
        throwsStateError,
      );
    });
  });
}
