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
}
