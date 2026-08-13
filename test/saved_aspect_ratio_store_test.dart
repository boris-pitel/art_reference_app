import 'package:art_reference_app/models/saved_aspect_ratio.dart';
import 'package:art_reference_app/services/saved_aspect_ratio_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves custom ratios and recognizes equivalent duplicates', () async {
    const store = SavedAspectRatioStore();

    final added = await store.add(const SavedAspectRatio(width: 4, height: 6));
    final duplicate = await store.add(
      const SavedAspectRatio(width: 2, height: 3),
    );

    expect(added.status, SaveAspectRatioStatus.added);
    expect(duplicate.status, SaveAspectRatioStatus.duplicate);
    expect(await store.load(), hasLength(1));
  });

  test('limits saved custom ratios to ten', () async {
    const store = SavedAspectRatioStore();
    for (var index = 1; index <= SavedAspectRatioStore.maximumRatios; index++) {
      final result = await store.add(
        SavedAspectRatio(width: index.toDouble(), height: 11),
      );
      expect(result.status, SaveAspectRatioStatus.added);
    }

    final overflow = await store.add(
      const SavedAspectRatio(width: 12, height: 11),
    );

    expect(overflow.status, SaveAspectRatioStatus.limitReached);
    expect(await store.load(), hasLength(10));
  });

  test('removes a saved custom ratio', () async {
    const store = SavedAspectRatioStore();
    const ratio = SavedAspectRatio(width: 8.5, height: 11);
    await store.add(ratio);

    await store.remove(ratio.key);

    expect(await store.load(), isEmpty);
  });
}
