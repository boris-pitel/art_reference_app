import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reference_category.dart';

class CategoryService {
  CategoryService(this._supabase);

  final SupabaseClient _supabase;

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

    return response
        .map(
          (row) => ReferenceCategory.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
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

    return ReferenceCategory.fromJson(
      Map<String, dynamic>.from(response),
    );
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
