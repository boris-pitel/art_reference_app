import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reference_category.dart';
import 'user_activity_logger.dart';

class CategoryDeletionResult {
  const CategoryDeletionResult({required this.movedToInbox});

  final int movedToInbox;

  factory CategoryDeletionResult.fromResponse(dynamic data) {
    if (data is! Map || data['deleted'] != true) {
      throw StateError(
        data is Map && data['error'] != null
            ? data['error'].toString()
            : 'The category could not be deleted.',
      );
    }

    final movedToInbox = data['moved_to_inbox'];
    if (movedToInbox != null && (movedToInbox is! num || movedToInbox < 0)) {
      throw StateError(
        'delete-category returned an invalid moved_to_inbox count: $data',
      );
    }

    return CategoryDeletionResult(
      movedToInbox: (movedToInbox as num?)?.toInt() ?? 0,
    );
  }
}

class CategoryService {
  CategoryService(this._supabase);

  final SupabaseClient _supabase;
  static const String _coverBucket = 'category-covers';

  String get _normalizedUserEmail {
    final email = _supabase.auth.currentUser?.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      throw StateError('You must be signed in before accessing categories.');
    }

    return email;
  }

  String get _userId {
    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$_normalizedUserEmail',
    );
  }

  Future<List<ReferenceCategory>> listCategories() async {
    final response = await _supabase
        .from('reference_categories')
        .select()
        .or('is_builtin.eq.true,user_id.eq.$_userId')
        .order('id', ascending: true);
    final authId = _supabase.auth.currentUser?.id;
    final overrides = authId == null
        ? const <dynamic>[]
        : await _supabase
              .from('user_category_cover_overrides')
              .select('category_code,storage_path')
              .eq('auth_user_id', authId);
    final overrideByCode = <String, String>{
      for (final row in overrides)
        if (row['category_code'] is String && row['storage_path'] is String)
          row['category_code'] as String: row['storage_path'] as String,
    };
    return Future.wait(
      response
          .where((row) {
            final category = ReferenceCategory.fromJson(
              Map<String, dynamic>.from(row),
            );
            return !category.isBuiltIn ||
                ReferenceCategory.visibleCategoryCodes.contains(
                  category.databaseCode,
                );
          })
          .map(
            (row) => _withResolvedCover(
              ReferenceCategory.fromJson(
                Map<String, dynamic>.from(row),
              ).copyWith(
                thumbnailAsset:
                    overrideByCode[row['code']] ??
                    row['thumbnail_asset'] as String?,
              ),
            ),
          ),
    );
  }

  Future<List<ReferenceCategory>> applySavedOrder(
    List<ReferenceCategory> categories,
  ) async {
    final authId = _supabase.auth.currentUser?.id;
    if (authId == null) throw StateError('You must be signed in.');
    final rows = await _supabase
        .from('user_category_order')
        .select('category_code,position')
        .eq('auth_user_id', authId)
        .order('position');
    final savedPositions = <String, int>{
      for (final row in rows)
        if (row['category_code'] is String && row['position'] is num)
          row['category_code'] as String: (row['position'] as num).toInt(),
    };
    const defaults = <String>[
      'my_art',
      'inbox',
      'portrait',
      'landscape',
      'still_life',
    ];
    final defaultPositions = <String, int>{
      for (var index = 0; index < defaults.length; index++)
        defaults[index]: index,
    };
    final result = List<ReferenceCategory>.of(categories);
    result.sort((left, right) {
      if (savedPositions.isNotEmpty) {
        final leftSaved = savedPositions[left.databaseCode];
        final rightSaved = savedPositions[right.databaseCode];
        if (leftSaved != null && rightSaved != null) {
          return leftSaved.compareTo(rightSaved);
        }
        if (leftSaved != null) return -1;
        if (rightSaved != null) return 1;
      }
      final leftDefault = defaultPositions[left.databaseCode];
      final rightDefault = defaultPositions[right.databaseCode];
      if (leftDefault != null && rightDefault != null) {
        return leftDefault.compareTo(rightDefault);
      }
      if (leftDefault != null) return -1;
      if (rightDefault != null) return 1;
      return left.id.compareTo(right.id);
    });
    final currentCodes = result.map((item) => item.databaseCode).toSet();
    if (savedPositions.length != result.length ||
        !savedPositions.keys.every(currentCodes.contains)) {
      await saveCategoryOrder(result);
    }
    return result;
  }

  Future<void> saveCategoryOrder(List<ReferenceCategory> categories) async {
    final authId = _supabase.auth.currentUser?.id;
    if (authId == null) throw StateError('You must be signed in.');
    await _supabase.from('user_category_order').upsert([
      for (var index = 0; index < categories.length; index++)
        {
          'auth_user_id': authId,
          'category_code': categories[index].databaseCode,
          'position': index,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
    ]);
    final rows = await _supabase
        .from('user_category_order')
        .select('category_code')
        .eq('auth_user_id', authId);
    final currentCodes = categories.map((item) => item.databaseCode).toSet();
    for (final row in rows) {
      final code = row['category_code'] as String?;
      if (code != null && !currentCodes.contains(code)) {
        await _supabase
            .from('user_category_order')
            .delete()
            .eq('auth_user_id', authId)
            .eq('category_code', code);
      }
    }
  }

  Future<ReferenceCategory> _withResolvedCover(
    ReferenceCategory category,
  ) async {
    const prefix = 'storage://category-covers/';
    final stored = category.thumbnailAsset;
    if (stored == null || !stored.startsWith(prefix)) return category;
    final url = await _supabase.storage
        .from(_coverBucket)
        .createSignedUrl(stored.substring(prefix.length), 3600);
    return category.copyWith(thumbnailAsset: url);
  }

  Future<ReferenceCategory> addCategory(String name) async {
    final normalizedName = validateName(name);

    final existingCategories = await listCategories();

    final duplicateNameExists = existingCategories.any(
      (category) =>
          category.displayName.toLowerCase() == normalizedName.toLowerCase(),
    );

    if (duplicateNameExists) {
      throw StateError('A category with this name already exists.');
    }

    final code = createUniqueCode(
      normalizedName,
      existingCategories.map((category) => category.databaseCode).toSet(),
    );

    late final Map<String, dynamic> response;
    try {
      response = await _supabase
          .from('reference_categories')
          .insert({
            'user_id': _userId,
            'code': code,
            'display_name': normalizedName,
            'thumbnail_asset': null,
            'is_builtin': false,
          })
          .select()
          .single();
    } on PostgrestException catch (error) {
      if (isUniqueConstraintViolation(error)) {
        throw StateError('A category with this name already exists.');
      }
      rethrow;
    }
    final created = ReferenceCategory.fromJson(
      Map<String, dynamic>.from(response),
    );
    UserActivityLogger.instance.record(
      operation: 'category_create',
      status: 'succeeded',
      targetType: 'category',
      targetId: created.id.toString(),
      details: {'category_code': created.databaseCode},
    );
    return created;
  }

  Future<ReferenceCategory> renameCategory(
    ReferenceCategory category,
    String name,
  ) async {
    _checkOwnedCategory(category);
    final value = validateName(name);
    final duplicate = (await listCategories()).any(
      (item) =>
          item.id != category.id &&
          item.displayName.toLowerCase() == value.toLowerCase(),
    );
    if (duplicate) {
      throw StateError('A category with this name already exists.');
    }
    final row = await _supabase
        .from('reference_categories')
        .update({'display_name': value})
        .eq('id', category.id)
        .eq('user_id', _userId)
        .eq('is_builtin', false)
        .select()
        .single();
    UserActivityLogger.instance.record(
      operation: 'category_rename',
      status: 'succeeded',
      targetType: 'category',
      targetId: category.id.toString(),
    );
    return _withResolvedCover(
      ReferenceCategory.fromJson(Map<String, dynamic>.from(row)),
    );
  }

  Future<ReferenceCategory> uploadCover(
    ReferenceCategory category,
    Uint8List bytes,
  ) async {
    if (!category.canChangeImage) {
      throw StateError('${category.displayName} image cannot be changed.');
    }
    if (bytes.isEmpty) throw ArgumentError('The selected image is empty.');
    final authId = _supabase.auth.currentUser?.id;
    if (authId == null) throw StateError('You must be signed in.');
    if (!category.isBuiltIn) _checkOwnedCategory(category);
    final path = category.isBuiltIn
        ? '$authId/builtin/${category.databaseCode}/cover.jpg'
        : '$authId/${category.id}/cover.jpg';
    await _supabase.storage
        .from(_coverBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    final coverUrl = 'storage://category-covers/$path';
    if (category.isBuiltIn) {
      await _supabase.from('user_category_cover_overrides').upsert({
        'auth_user_id': authId,
        'category_code': category.databaseCode,
        'storage_path': coverUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      await _supabase
          .from('reference_categories')
          .update({'thumbnail_asset': coverUrl})
          .eq('id', category.id)
          .eq('user_id', _userId)
          .eq('is_builtin', false);
    }
    UserActivityLogger.instance.record(
      operation: 'category_cover_update',
      status: 'succeeded',
      targetType: 'category',
      targetId: category.id.toString(),
      details: {'bytes': bytes.lengthInBytes},
    );
    return _withResolvedCover(category.copyWith(thumbnailAsset: coverUrl));
  }

  Future<void> deleteCategory(ReferenceCategory category) async {
    _checkOwnedCategory(category);
    final response = await _supabase.functions.invoke(
      'delete-category',
      body: {'category_id': category.id},
    );
    final deletion = CategoryDeletionResult.fromResponse(response.data);
    final authId = _supabase.auth.currentUser?.id;
    if (authId != null) {
      try {
        await _supabase.storage.from(_coverBucket).remove([
          '$authId/${category.id}/cover.jpg',
        ]);
      } catch (_) {}
    }
    UserActivityLogger.instance.record(
      operation: 'category_delete',
      status: 'succeeded',
      targetType: 'category',
      targetId: category.id.toString(),
      details: {
        'category_code': category.databaseCode,
        'moved_to_inbox': deletion.movedToInbox,
      },
    );
  }

  static String validateName(String name) {
    final value = name.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Category name cannot be empty.');
    }
    if (value.length > 60) {
      throw ArgumentError.value(
        name,
        'name',
        'Category name cannot be longer than 60 characters.',
      );
    }
    return value;
  }

  static bool isUniqueConstraintViolation(PostgrestException error) {
    return error.code == '23505';
  }

  static void ensureOwnedCategory(
    ReferenceCategory category, {
    required String userId,
  }) {
    if (category.isBuiltIn) {
      throw StateError('Built-in categories cannot be changed.');
    }
    if (category.userId != userId) {
      throw StateError('This category belongs to another user.');
    }
  }

  void _checkOwnedCategory(ReferenceCategory category) {
    ensureOwnedCategory(category, userId: _userId);
  }

  static String createUniqueCode(String name, Set<String> existingCodes) {
    var baseCode = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    if (baseCode.isEmpty) {
      baseCode = 'category';
    }

    var candidate = baseCode;
    var suffix = 2;

    while (existingCodes.contains(candidate)) {
      candidate = '${baseCode}_$suffix';
      suffix++;
    }

    return candidate;
  }
}
