import 'package:art_reference_app/models/reference_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('My Art is a protected generated category', () {
    expect(ReferenceCategory.myArt.isMyArt, isTrue);
    expect(ReferenceCategory.myArt.isBuiltIn, isTrue);
    expect(ReferenceCategory.myArt.canDelete, isFalse);
    expect(ReferenceCategory.myArt.canRename, isFalse);
  });
}
