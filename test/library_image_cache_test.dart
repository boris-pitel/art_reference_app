import 'package:art_reference_app/services/library_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps image listings separate for each user and category', () async {
    await LibraryImageCache.write('user-a', 'category:portrait', [
      {'id': 'a'},
    ]);
    await LibraryImageCache.write('user-b', 'category:portrait', [
      {'id': 'b'},
    ]);

    expect(await LibraryImageCache.read('user-a', 'category:portrait'), [
      {'id': 'a'},
    ]);
    expect(await LibraryImageCache.read('user-b', 'category:portrait'), [
      {'id': 'b'},
    ]);
    expect(await LibraryImageCache.read('user-a', 'category:inbox'), isNull);
  });

  test('account deletion clears only that user image listings', () async {
    await LibraryImageCache.write('user-a', 'category:portrait', [
      {'id': 'a'},
    ]);
    await LibraryImageCache.write('user-b', 'category:portrait', [
      {'id': 'b'},
    ]);

    await LibraryImageCache.clearUser('user-a');

    expect(await LibraryImageCache.read('user-a', 'category:portrait'), isNull);
    expect(await LibraryImageCache.read('user-b', 'category:portrait'), [
      {'id': 'b'},
    ]);
  });
}
