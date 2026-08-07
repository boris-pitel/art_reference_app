import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reference_category.dart';
import 'user_activity_logger.dart';

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
    return Future.wait(
      response.map(
        (row) => _withResolvedCover(
          ReferenceCategory.fromJson(Map<String, dynamic>.from(row)),
        ),
      ),
    );
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
    final normalizedName = name.trim();

    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Category name cannot be empty.');
    }

    if (normalizedName.length > 60) {
      throw ArgumentError.value(
        name,
        'name',
        'Category name cannot be longer than 60 characters.',
      );
    }

    final existingCategories = await listCategories();

    final duplicateNameExists = existingCategories.any(
      (category) =>
          category.displayName.toLowerCase() == normalizedName.toLowerCase(),
    );

    if (duplicateNameExists) {
      throw StateError('A category with this name already exists.');
    }

    final code = _createUniqueCode(
      normalizedName,
      existingCategories.map((category) => category.databaseCode).toSet(),
    );

    final response = await _supabase
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
    final value = _validateName(name);
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
    _checkOwnedCategory(category);
    if (bytes.isEmpty) throw ArgumentError('The selected image is empty.');
    final authId = _supabase.auth.currentUser?.id;
    if (authId == null) throw StateError('You must be signed in.');
    final path = '$authId/${category.id}/cover.jpg';
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
    final row = await _supabase
        .from('reference_categories')
        .update({'thumbnail_asset': coverUrl})
        .eq('id', category.id)
        .eq('user_id', _userId)
        .eq('is_builtin', false)
        .select()
        .single();
    UserActivityLogger.instance.record(
      operation: 'category_cover_update',
      status: 'succeeded',
      targetType: 'category',
      targetId: category.id.toString(),
      details: {'bytes': bytes.lengthInBytes},
    );
    return _withResolvedCover(
      ReferenceCategory.fromJson(Map<String, dynamic>.from(row)),
    );
  }

  Future<void> deleteCategory(ReferenceCategory category) async {
    _checkOwnedCategory(category);
    final ownedImages = await _supabase
        .from('image_assets')
        .select('id')
        .eq('user_id', _userId);
    final ids = ownedImages.map((row) => row['id'] as String).toList();
    if (ids.isNotEmpty) {
      await _supabase
          .from('image_categories')
          .delete()
          .eq('category_code', category.databaseCode)
          .inFilter('image_id', ids);
    }
    await _supabase
        .from('reference_categories')
        .delete()
        .eq('id', category.id)
        .eq('user_id', _userId)
        .eq('is_builtin', false);
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
      details: {'category_code': category.databaseCode},
    );
  }

  String _validateName(String name) {
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

  void _checkOwnedCategory(ReferenceCategory category) {
    if (category.isBuiltIn || category.userId != _userId) {
      throw StateError('Built-in categories cannot be changed.');
    }
  }

  String _createUniqueCode(String name, Set<String> existingCodes) {
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
