import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reference_category.dart';

class LibraryHomeSnapshot {
  const LibraryHomeSnapshot({required this.categories, required this.counts});

  final List<ReferenceCategory> categories;
  final Map<String, int> counts;
}

class LibraryHomeCache {
  static const _prefix = 'library_home_v1_';

  static Future<LibraryHomeSnapshot?> read(String userId) async {
    final value = (await SharedPreferences.getInstance()).getString(
      '$_prefix$userId',
    );
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      final categories = (json['categories'] as List<dynamic>)
          .map(
            (item) => ReferenceCategory.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      final counts = Map<String, dynamic>.from(
        json['counts'] as Map,
      ).map((key, value) => MapEntry(key, (value as num).toInt()));
      return LibraryHomeSnapshot(categories: categories, counts: counts);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    String userId,
    List<ReferenceCategory> categories,
    Map<String, int> counts,
  ) async {
    final value = jsonEncode({
      'categories': categories
          .map(
            (item) => {
              'id': item.id,
              'code': item.databaseCode,
              'display_name': item.displayName,
              'thumbnail_asset': item.thumbnailAsset,
              'is_builtin': item.isBuiltIn,
              'user_id': item.userId,
            },
          )
          .toList(growable: false),
      'counts': counts,
    });
    await (await SharedPreferences.getInstance()).setString(
      '$_prefix$userId',
      value,
    );
  }
}
