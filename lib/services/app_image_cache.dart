import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps images on the device so they are fetched once rather than every time.
///
/// Keyed by image id, never by URL. Signed URLs carry an expiry that changes
/// every second, so a URL-keyed cache would miss on every request and fill the
/// disk with duplicate copies of the same photograph. The id is stable for the
/// life of the image, and editing produces a new id rather than changing an
/// existing one, so a cached entry can never be stale.
///
/// Roughly half of all image views in this app are repeat views of something
/// already seen, and those now cost no network at all.
class AppImageCache {
  const AppImageCache._();

  static const String _cacheName = 'painter_reference_images';

  /// The ids this device holds. flutter_cache_manager can remove a key and
  /// fetch one, but cannot list what it is holding — so the list is kept here,
  /// because eviction needs to know what exists in order to remove what should
  /// not.
  static const String _trackedKey = 'cached_image_keys';

  /// Long enough that a reference library survives a holiday, short enough that
  /// anything deleted on another device disappears even if reconciliation never
  /// runs on this one.
  static const Duration _maximumAge = Duration(days: 30);
  static const int _maximumObjects = 800;

  static final CacheManager _manager = CacheManager(
    Config(
      _cacheName,
      stalePeriod: _maximumAge,
      maxNrOfCacheObjects: _maximumObjects,
    ),
  );

  static CacheManager get manager => _manager;

  /// The full-size image.
  static String fullKey(String imageId) => 'full:$imageId';

  /// The thumbnail, which is a different file for the same image and so needs
  /// a key of its own.
  static String thumbnailKey(String imageId) => 'thumb:$imageId';

  /// Records that a key is held, so eviction can find it later.
  static Future<void> track(String key) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final tracked = preferences.getStringList(_trackedKey) ?? <String>[];
      if (tracked.contains(key)) return;

      tracked.add(key);
      await preferences.setStringList(_trackedKey, tracked);
    } catch (error) {
      // Losing the bookkeeping costs a later eviction, not correctness: the
      // cache still works, it just holds an entry longer than it should.
      debugPrint('Unable to track cached image $key: $error');
    }
  }

  /// Writes bytes the app already has, so the first view needs no network.
  ///
  /// Called after an upload. The image has just been sent from this device, so
  /// downloading it back to display it is the one fetch guaranteed to be
  /// unnecessary — and, on a slow connection, the one most likely to stall and
  /// leave the user looking at nothing.
  static Future<void> seed({
    required String key,
    required String url,
    required Uint8List bytes,
  }) async {
    try {
      await _manager.putFile(
        url,
        bytes,
        key: key,
        maxAge: _maximumAge,
        fileExtension: 'jpg',
      );
      await track(key);
    } catch (error) {
      debugPrint('Unable to seed the image cache for $key: $error');
    }
  }

  /// Removes everything this device holds for images the user no longer has.
  ///
  /// [liveImageIds] must be the complete set the user can see. A partial or
  /// failed list must never reach here: deleting a hundred good entries costs
  /// far more than keeping one stale one, so callers pass null rather than a
  /// guess, and this does nothing.
  /// Splits held keys into those to keep and those to drop.
  ///
  /// Separated from the eviction itself so the decision can be tested without
  /// a filesystem — this is the part that, if wrong, deletes images somebody
  /// still owns.
  @visibleForTesting
  static ({List<String> keep, List<String> remove}) partition({
    required List<String> tracked,
    required Set<String>? liveImageIds,
  }) {
    if (liveImageIds == null || liveImageIds.isEmpty) {
      return (keep: tracked, remove: const <String>[]);
    }

    final keep = <String>[];
    final remove = <String>[];

    for (final key in tracked) {
      final separator = key.indexOf(':');
      final imageId = separator < 0 ? key : key.substring(separator + 1);
      (liveImageIds.contains(imageId) ? keep : remove).add(key);
    }

    return (keep: keep, remove: remove);
  }

  static Future<int> evictMissing(Set<String>? liveImageIds) async {
    if (liveImageIds == null || liveImageIds.isEmpty) return 0;

    try {
      final preferences = await SharedPreferences.getInstance();
      final tracked = preferences.getStringList(_trackedKey) ?? <String>[];
      if (tracked.isEmpty) return 0;

      final split = partition(tracked: tracked, liveImageIds: liveImageIds);
      final keep = split.keep;
      final remove = split.remove;

      for (final key in remove) {
        await _manager.removeFile(key);
      }

      if (remove.isNotEmpty) {
        await preferences.setStringList(_trackedKey, keep);
      }

      return remove.length;
    } catch (error) {
      debugPrint('Unable to evict cached images: $error');
      return 0;
    }
  }

  /// Empties the cache entirely.
  ///
  /// Called on sign-out and on account deletion. Without this, one person's
  /// photographs would still be on the device after somebody else signs in,
  /// which would quietly contradict what the privacy policy promises about
  /// deletion.
  static Future<void> clear() async {
    try {
      await _manager.emptyCache();
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_trackedKey);
    } catch (error) {
      debugPrint('Unable to clear the image cache: $error');
    }
  }
}
