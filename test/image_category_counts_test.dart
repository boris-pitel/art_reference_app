import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';

ReferenceCategory _category(String code) => ReferenceCategory(
  id: 1,
  databaseCode: code,
  displayName: code,
  isBuiltIn: false,
);

void main() {
  group('ImageCategoryCounts', () {
    const counts = ImageCategoryCounts(
      byCategoryCode: {'portrait': 51, 'landscape': 27, 'inbox': 0},
      finishedArtwork: 6,
    );

    test('reads a stored category by its database code', () {
      expect(counts.countFor(_category('portrait')), 51);
      expect(counts.countFor(_category('landscape')), 27);
    });

    test('distinguishes an empty category from an absent one', () {
      // Both show zero, but only one of them was actually reported. Neither may
      // read as null on the home screen.
      expect(counts.countFor(_category('inbox')), 0);
      expect(counts.countFor(_category('never_used')), 0);
    });

    test('routes My Art to the finished artwork count', () {
      // My Art is not a row in image_categories, so looking it up by database
      // code would always report zero however many artworks exist.
      expect(counts.countFor(ReferenceCategory.myArt), 6);
      expect(counts.byCategoryCode.containsKey('my_art'), isFalse);
    });

    test('reports zero artworks rather than falling back to a category', () {
      const empty = ImageCategoryCounts(
        byCategoryCode: {'my_art': 99},
        finishedArtwork: 0,
      );

      expect(empty.countFor(ReferenceCategory.myArt), 0);
    });
  });
}
