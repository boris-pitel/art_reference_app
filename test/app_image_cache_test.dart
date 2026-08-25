import 'package:art_reference_app/services/app_image_cache.dart';
import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('cache keys', () {
    test('a full image and its thumbnail are separate entries', () {
      // Two different files describe the same image. Sharing a key would mean
      // whichever loaded first was shown in both places.
      expect(
        AppImageCache.fullKey('abc'),
        isNot(AppImageCache.thumbnailKey('abc')),
      );
    });

    test('keys carry the image id, which is what eviction matches on', () {
      expect(AppImageCache.fullKey('abc'), contains('abc'));
      expect(AppImageCache.thumbnailKey('abc'), contains('abc'));
    });
  });

  group('eviction', () {
    test('keeps only what the server still lists', () {
      final split = AppImageCache.partition(
        tracked: [
          AppImageCache.fullKey('kept'),
          AppImageCache.thumbnailKey('kept'),
          AppImageCache.fullKey('deleted'),
        ],
        liveImageIds: {'kept'},
      );

      expect(split.keep, [
        AppImageCache.fullKey('kept'),
        AppImageCache.thumbnailKey('kept'),
      ]);
      expect(split.remove, [AppImageCache.fullKey('deleted')]);
    });

    test('drops every entry for a deleted image, not just one', () {
      // Full and thumbnail are separate files. Removing one and keeping the
      // other would leave a deleted photograph visible in the grid.
      final split = AppImageCache.partition(
        tracked: [
          AppImageCache.fullKey('gone'),
          AppImageCache.thumbnailKey('gone'),
        ],
        liveImageIds: {'other'},
      );

      expect(split.remove, hasLength(2));
      expect(split.keep, isEmpty);
    });

    test('keeps everything when the list is missing or empty', () {
      final tracked = [AppImageCache.fullKey('kept')];

      for (final ids in [null, const <String>{}]) {
        final split = AppImageCache.partition(
          tracked: tracked,
          liveImageIds: ids,
        );

        expect(split.remove, isEmpty);
        expect(split.keep, tracked);
      }
    });

    test('does nothing when the list is absent', () async {
      // The dangerous case. A failed request must never read as "this person
      // owns nothing", which would delete the entire cache.
      await AppImageCache.track(AppImageCache.fullKey('kept'));

      expect(await AppImageCache.evictMissing(null), 0);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('cached_image_keys'), hasLength(1));
    });

    test('does nothing when the list is empty', () async {
      // Also treated as unusable rather than authoritative: an empty answer is
      // far more likely to be a bug than a user who genuinely owns nothing.
      await AppImageCache.track(AppImageCache.fullKey('kept'));

      expect(await AppImageCache.evictMissing(const <String>{}), 0);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('cached_image_keys'), hasLength(1));
    });

    test('tracking the same key twice does not duplicate it', () async {
      await AppImageCache.track(AppImageCache.fullKey('one'));
      await AppImageCache.track(AppImageCache.fullKey('one'));

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getStringList('cached_image_keys'), hasLength(1));
    });
  });

  group('ImageCategoryCounts.ownedImageIds', () {
    test('is null when the server sent no list', () {
      // Distinct from an empty set, and the distinction is what stops a server
      // that has not been redeployed from wiping every device's cache.
      const counts = ImageCategoryCounts(
        byCategoryCode: {'portrait': 3},
        finishedArtwork: 0,
      );

      expect(counts.ownedImageIds, isNull);
    });

    test('carries the ids when the server sent them', () {
      const counts = ImageCategoryCounts(
        byCategoryCode: {},
        finishedArtwork: 0,
        ownedImageIds: {'a', 'b'},
      );

      expect(counts.ownedImageIds, {'a', 'b'});
    });
  });
}
