import 'package:art_reference_app/models/reference_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('My Art is a protected generated category', () {
    expect(ReferenceCategory.myArt.isMyArt, isTrue);
    expect(ReferenceCategory.myArt.isBuiltIn, isTrue);
    expect(ReferenceCategory.myArt.canDelete, isFalse);
    expect(ReferenceCategory.myArt.canRename, isFalse);
    expect(
      ReferenceCategory.myArt.thumbnailAsset,
      'assets/category_thumbnails/myart.jpg',
    );
  });

  test('normalizes the legacy Icon category name', () {
    final category = ReferenceCategory.fromJson({
      'id': 6,
      'code': 'icon',
      'display_name': 'Icon',
      'is_builtin': true,
    });

    expect(category.displayName, 'Icons');
  });

  test('reference and custom categories allow personalized cover images', () {
    for (final code in ['portrait', 'landscape', 'still_life']) {
      final category = ReferenceCategory.fromJson({
        'id': code.hashCode,
        'code': code,
        'display_name': code,
        'is_builtin': true,
      });
      expect(category.canChangeImage, isTrue);
    }

    expect(ReferenceCategory.myArt.canChangeImage, isFalse);
    final inbox = ReferenceCategory.fromJson({
      'id': 99,
      'code': 'inbox',
      'display_name': 'Inbox',
      'is_builtin': true,
    });
    expect(inbox.isInbox, isTrue);
    expect(inbox.canChangeImage, isFalse);
    final custom = ReferenceCategory.fromJson({
      'id': 100,
      'code': 'flowers',
      'display_name': 'Flowers',
      'is_builtin': false,
      'user_id': 'owner',
    });
    expect(custom.canChangeImage, isTrue);
  });
}
