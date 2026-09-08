import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last server-issued image listing for a category or relationship.
///
/// Signed URLs in the snapshot can expire, but image widgets use stable cache
/// keys. Therefore downloaded files still open offline; an image that was
/// never downloaded shows its ordinary unavailable placeholder.
class LibraryImageCache {
  const LibraryImageCache._();

  static const String _prefix = 'library_images_v1_';

  static String _key(String userId, String scope) =>
      '$_prefix${Uri.encodeComponent(userId)}_${Uri.encodeComponent(scope)}';

  static Future<List<dynamic>?> read(String userId, String scope) async {
    final value = (await SharedPreferences.getInstance()).getString(
      _key(userId, scope),
    );
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(
    String userId,
    String scope,
    List<dynamic> rows,
  ) async {
    await (await SharedPreferences.getInstance()).setString(
      _key(userId, scope),
      jsonEncode(rows),
    );
  }

  static Future<void> clearUser(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final userPrefix = '$_prefix${Uri.encodeComponent(userId)}_';
    for (final key in preferences.getKeys()) {
      if (key.startsWith(userPrefix)) await preferences.remove(key);
    }
  }
}
