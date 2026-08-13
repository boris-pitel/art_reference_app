import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'user_activity_logger.dart';

class ImageKeyword {
  const ImageKeyword({
    required this.id,
    required this.imageId,
    required this.keyword,
    required this.dateAdded,
  });

  final int id;
  final String imageId;
  final String keyword;
  final DateTime dateAdded;

  factory ImageKeyword.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final imageId = json['image_id'];
    final keyword = json['keyword'];
    final dateAdded = json['date_added'];

    if (id is! int) {
      throw StateError('Invalid keyword ID returned by Supabase: $json');
    }

    if (imageId is! String || imageId.trim().isEmpty) {
      throw StateError('Invalid image ID returned by Supabase: $json');
    }

    if (keyword is! String || keyword.trim().isEmpty) {
      throw StateError('Invalid keyword returned by Supabase: $json');
    }

    if (dateAdded is! String || dateAdded.trim().isEmpty) {
      throw StateError('Invalid keyword date returned by Supabase: $json');
    }

    return ImageKeyword(
      id: id,
      imageId: imageId.trim(),
      keyword: keyword.trim(),
      dateAdded: DateTime.parse(dateAdded),
    );
  }
}

class DuplicateKeywordException implements Exception {
  const DuplicateKeywordException(this.keyword);

  final String keyword;

  @override
  String toString() {
    return 'The keyword "$keyword" is already attached to this image.';
  }
}

class KeywordService {
  KeywordService(this._supabase);

  final SupabaseClient _supabase;

  static const String _tableName = 'image_keywords';

  String get _normalizedUserEmail {
    final email = _supabase.auth.currentUser?.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      throw StateError('You must be signed in before accessing keywords.');
    }

    return email;
  }

  String get _userId {
    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$_normalizedUserEmail',
    );
  }

  Future<List<ImageKeyword>> listKeywords(String imageId) async {
    final normalizedImageId = imageId.trim();

    if (normalizedImageId.isEmpty) {
      throw ArgumentError.value(
        imageId,
        'imageId',
        'The image ID cannot be empty.',
      );
    }

    final response = await _supabase
        .from(_tableName)
        .select('id, image_id, keyword, date_added')
        .eq('user_id', _userId)
        .eq('image_id', normalizedImageId)
        .order('keyword', ascending: true);

    return response
        .map((row) => ImageKeyword.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ImageKeyword>> searchKeywords(String query) async {
    final normalizedQuery = query.trim();

    if (normalizedQuery.isEmpty) {
      return const <ImageKeyword>[];
    }

    final response = await _supabase
        .from(_tableName)
        .select('id, image_id, keyword, date_added')
        .eq('user_id', _userId)
        .ilike('keyword', '%$normalizedQuery%')
        .order('keyword', ascending: true);

    return response
        .map((row) => ImageKeyword.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<ImageKeyword> addKeyword({
    required String imageId,
    required String keyword,
  }) async {
    final normalizedImageId = imageId.trim();
    final normalizedKeyword = normalizeKeyword(keyword);

    if (normalizedImageId.isEmpty) {
      throw ArgumentError.value(
        imageId,
        'imageId',
        'The image ID cannot be empty.',
      );
    }

    try {
      final response = await _supabase
          .from(_tableName)
          .insert({
            'user_id': _userId,
            'image_id': normalizedImageId,
            'keyword': normalizedKeyword,
          })
          .select('id, image_id, keyword, date_added')
          .single();

      final created = ImageKeyword.fromJson(
        Map<String, dynamic>.from(response),
      );
      UserActivityLogger.instance.record(
        operation: 'keyword_add',
        status: 'succeeded',
        targetType: 'image',
        targetId: normalizedImageId,
        details: {'keyword_id': created.id},
      );
      return created;
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw DuplicateKeywordException(normalizedKeyword);
      }

      rethrow;
    }
  }

  Future<void> deleteKeyword(ImageKeyword keyword) async {
    await _supabase
        .from(_tableName)
        .delete()
        .eq('id', keyword.id)
        .eq('user_id', _userId)
        .eq('image_id', keyword.imageId);
    UserActivityLogger.instance.record(
      operation: 'keyword_delete',
      status: 'succeeded',
      targetType: 'image',
      targetId: keyword.imageId,
      details: {'keyword_id': keyword.id},
    );
  }

  static String normalizeKeyword(String keyword) {
    final normalizedKeyword = keyword.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (normalizedKeyword.isEmpty) {
      throw ArgumentError('The keyword cannot be empty.');
    }

    if (normalizedKeyword.length > 100) {
      throw ArgumentError('The keyword must be 100 characters or fewer.');
    }

    return normalizedKeyword;
  }
}
