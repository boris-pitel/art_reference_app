import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/services/category_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryService.validateName', () {
    test('trims a valid category name', () {
      expect(CategoryService.validateName('  Flowers  '), 'Flowers');
    });

    test('rejects empty and whitespace-only names', () {
      for (final value in ['', '   ', '\n\t']) {
        expect(
          () => CategoryService.validateName(value),
          throwsA(isA<ArgumentError>()),
          reason: 'value: "$value"',
        );
      }
    });

    test('enforces the 60-character limit', () {
      expect(CategoryService.validateName('a' * 60), hasLength(60));
      expect(
        () => CategoryService.validateName('a' * 61),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CategoryService.createUniqueCode', () {
    test('normalizes punctuation and casing', () {
      expect(
        CategoryService.createUniqueCode('  Plein Air & Light ', {}),
        'plein_air_light',
      );
    });

    test('increments through every existing collision', () {
      expect(
        CategoryService.createUniqueCode('Flowers', {
          'flowers',
          'flowers_2',
          'flowers_3',
        }),
        'flowers_4',
      );
    });

    test('uses a stable fallback for punctuation-only names', () {
      expect(
        CategoryService.createUniqueCode('***', {'category', 'category_2'}),
        'category_3',
      );
    });
  });
  group('CategoryService ownership rules', () {
    const owned = ReferenceCategory(
      id: 10,
      databaseCode: 'flowers',
      displayName: 'Flowers',
      isBuiltIn: false,
      userId: 'owner-id',
    );
    const foreign = ReferenceCategory(
      id: 11,
      databaseCode: 'figures',
      displayName: 'Figures',
      isBuiltIn: false,
      userId: 'other-id',
    );

    test('allows only a custom category owned by the current user', () {
      expect(
        () => CategoryService.ensureOwnedCategory(owned, userId: 'owner-id'),
        returnsNormally,
      );
      expect(
        () => CategoryService.ensureOwnedCategory(
          ReferenceCategory.myArt,
          userId: 'owner-id',
        ),
        throwsStateError,
      );
      expect(
        () => CategoryService.ensureOwnedCategory(foreign, userId: 'owner-id'),
        throwsStateError,
      );
    });
  });

  group('CategoryDeletionResult', () {
    test('reads the number of references preserved in Inbox', () {
      final result = CategoryDeletionResult.fromResponse({
        'deleted': true,
        'moved_to_inbox': 3,
      });
      expect(result.movedToInbox, 3);
      expect(
        CategoryDeletionResult.fromResponse({'deleted': true}).movedToInbox,
        0,
      );
    });

    test('rejects backend errors and invalid counts', () {
      expect(
        () => CategoryDeletionResult.fromResponse({'error': 'Not owned'}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Not owned',
          ),
        ),
      );
      expect(
        () => CategoryDeletionResult.fromResponse({
          'deleted': true,
          'moved_to_inbox': -1,
        }),
        throwsStateError,
      );
    });
  });

  test('recognizes database unique-constraint races', () {
    expect(
      CategoryService.isUniqueConstraintViolation(
        const PostgrestException(message: 'duplicate', code: '23505'),
      ),
      isTrue,
    );
    expect(
      CategoryService.isUniqueConstraintViolation(
        const PostgrestException(message: 'failure', code: 'PGRST100'),
      ),
      isFalse,
    );
  });
}
