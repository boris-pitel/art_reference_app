import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ImageSearchResult {
  const ImageSearchResult({
    required this.id,
    required this.dateAdded,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.displayUrl,
    required this.title,
    required this.notes,
    required this.originalOwnerName,
    required this.matchingKeywords,
    required this.matchedIn,
  });

  final String id;
  final DateTime dateAdded;
  final String imageUrl;
  final String? thumbnailUrl;
  final String? displayUrl;
  final String? title;
  final String? notes;
  final String? originalOwnerName;
  final List<String> matchingKeywords;
  final List<String> matchedIn;

  factory ImageSearchResult.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final dateAdded = json['date_added'];
    final imageUrl = json['image_url'];
    final thumbnailUrl = json['thumbnail_url'];
    final title = json['title'];
    final notes = json['notes'];
    final originalOwnerName = json['original_owner_name'];

    if (id is! String || id.trim().isEmpty) {
      throw StateError('Invalid image ID returned by search-images: $json');
    }
    if (dateAdded is! String || dateAdded.trim().isEmpty) {
      throw StateError('Invalid date returned by search-images: $json');
    }
    if (imageUrl is! String || imageUrl.trim().isEmpty) {
      throw StateError('Invalid image URL returned by search-images: $json');
    }
    if (thumbnailUrl != null && thumbnailUrl is! String) {
      throw StateError(
        'Invalid thumbnail URL returned by search-images: $json',
      );
    }
    if (title != null && title is! String) {
      throw StateError('Invalid title returned by search-images: $json');
    }
    if (notes != null && notes is! String) {
      throw StateError('Invalid notes returned by search-images: $json');
    }
    if (originalOwnerName != null && originalOwnerName is! String) {
      throw StateError(
        'Invalid original_owner_name returned by search-images: $json',
      );
    }

    return ImageSearchResult(
      id: id.trim(),
      dateAdded: DateTime.parse(dateAdded),
      imageUrl: imageUrl.trim(),
      thumbnailUrl: thumbnailUrl is String && thumbnailUrl.trim().isNotEmpty
          ? thumbnailUrl.trim()
          : null,
      displayUrl: json['display_url'] is String
          ? (json['display_url'] as String).trim()
          : null,
      title: title is String && title.trim().isNotEmpty ? title.trim() : null,
      notes: notes is String && notes.trim().isNotEmpty ? notes.trim() : null,
      originalOwnerName:
          originalOwnerName is String && originalOwnerName.trim().isNotEmpty
          ? originalOwnerName.trim()
          : null,
      matchingKeywords: _stringList(json['matching_keywords']),
      matchedIn: _stringList(json['matched_in']),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }

    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class ImageSearchService {
  ImageSearchService(this._supabase);

  final SupabaseClient _supabase;

  String get _normalizedUserEmail {
    final email = _supabase.auth.currentUser?.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      throw StateError('You must be signed in before searching images.');
    }

    return email;
  }

  String get _userId {
    return const Uuid().v5(
      Namespace.url.value,
      'art-reference-user:$_normalizedUserEmail',
    );
  }

  static String normalizeQuery(String query) => query.trim();

  static bool shouldSkipSearch(
    String normalizedQuery, {
    required bool favoritesOnly,
  }) {
    return normalizedQuery.isEmpty && !favoritesOnly;
  }

  static List<ImageSearchResult> parseSearchResults(dynamic data) {
    if (data is Map && data['error'] != null) {
      throw StateError(data['error'].toString());
    }

    if (data is! List) {
      throw StateError('search-images returned an unexpected response: $data');
    }

    return data
        .map((item) {
          if (item is! Map) {
            throw StateError('search-images returned an invalid result: $item');
          }
          return ImageSearchResult.fromJson(Map<String, dynamic>.from(item));
        })
        .toList(growable: false);
  }

  Future<List<ImageSearchResult>> searchImages(
    String query, {
    bool favoritesOnly = false,
  }) async {
    final normalizedQuery = normalizeQuery(query);

    if (shouldSkipSearch(normalizedQuery, favoritesOnly: favoritesOnly)) {
      return const <ImageSearchResult>[];
    }

    final response = await _supabase.functions.invoke(
      'search-images',
      body: {
        'user_id': _userId,
        'query': normalizedQuery,
        'favorites_only': favoritesOnly,
      },
    );

    return parseSearchResults(response.data);
  }
}
