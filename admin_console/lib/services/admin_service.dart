import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

class UserInventory {
  const UserInventory({
    required this.user,
    required this.dataUserId,
    required this.images,
    required this.categories,
    required this.storagePathsByBucket,
  });

  final User user;
  final String dataUserId;
  final List<Map<String, dynamic>> images;
  final List<Map<String, dynamic>> categories;
  final Map<String, List<String>> storagePathsByBucket;

  String get email => user.email ?? '';
  int get storageFileCount => storagePathsByBucket.values.fold(
    0,
    (total, paths) => total + paths.length,
  );

  Map<String, Object?> toAuditDetails() => {
    'data_user_id': dataUserId,
    'images': images.length,
    'categories': categories.length,
    'storage_files': storageFileCount,
    'storage_by_bucket': {
      for (final entry in storagePathsByBucket.entries)
        entry.key: entry.value.length,
    },
  };
}

class AdminService {
  AdminService({required String url, required String secretKey})
    : client = SupabaseClient(
        url,
        secretKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

  final SupabaseClient client;

  static const _uuid = Uuid();
  static const _pageSize = 200;
  static const _storagePageSize = 1000;
  static const _feedbackBucket = 'feedback-attachments';
  static const _storageBuckets = ['reference-images', 'art-images'];
  static const _coverBucket = 'category-covers';

  String dataUserIdForEmail(String email) => _uuid.v5(
    Namespace.url.value,
    'art-reference-user:${normalizeEmail(email)}',
  );

  String normalizeEmail(String email) => email.trim().toLowerCase();

  Future<List<User>> listUsers() async {
    final users = <User>[];
    var page = 1;
    while (true) {
      final batch = await client.auth.admin.listUsers(
        page: page,
        perPage: _pageSize,
      );
      users.addAll(batch);
      if (batch.length < _pageSize) break;
      page += 1;
    }
    users.sort((a, b) => (a.email ?? '').compareTo(b.email ?? ''));
    return users;
  }

  Future<User> findUserByEmail(String email) async {
    final normalized = normalizeEmail(email);
    if (!_looksLikeEmail(normalized)) {
      throw ArgumentError.value(email, 'email', 'Enter a valid email address.');
    }
    final matches = (await listUsers())
        .where((user) => normalizeEmail(user.email ?? '') == normalized)
        .toList();
    if (matches.isEmpty) {
      throw StateError('No registered user was found for $normalized.');
    }
    if (matches.length > 1) {
      throw StateError('More than one Auth user matched $normalized.');
    }
    return matches.single;
  }

  Future<UserInventory> inventoryForEmail(String email) async {
    final user = await findUserByEmail(email);
    final normalized = normalizeEmail(user.email ?? email);
    final dataUserId = dataUserIdForEmail(normalized);
    final images = await _listImageRows(dataUserId);
    final categories = await _listCategoryRows(dataUserId);
    final paths = <String, Set<String>>{
      for (final bucket in [..._storageBuckets, _coverBucket, _feedbackBucket])
        bucket: <String>{},
    };

    for (final image in images) {
      for (final key in ['storage_path', 'thumbnail_storage_path']) {
        final value = image[key];
        if (value is String && value.trim().isNotEmpty) {
          paths['reference-images']!.add(value.trim());
        }
      }
    }
    for (final category in categories) {
      final value = category['thumbnail_asset'];
      const prefix = 'storage://category-covers/';
      if (value is String && value.startsWith(prefix)) {
        paths[_coverBucket]!.add(value.substring(prefix.length));
      }
    }

    for (final bucket in _storageBuckets) {
      paths[bucket]!.addAll(await _listStorageTree(bucket, dataUserId));
    }
    paths[_coverBucket]!.addAll(await _listStorageTree(_coverBucket, user.id));

    paths[_feedbackBucket]!.addAll(
      await _listStorageTree(_feedbackBucket, user.id),
    );
    return UserInventory(
      user: user,
      dataUserId: dataUserId,
      images: images,
      categories: categories,
      storagePathsByBucket: {
        for (final entry in paths.entries)
          entry.key: entry.value.toList()..sort(),
      },
    );
  }

  Future<Map<String, dynamic>> removeUser(UserInventory inventory) async {
    final databaseResult = await client.rpc(
      'admin_delete_user_data',
      params: {
        'target_user_id': inventory.dataUserId,
        'target_email': inventory.email,
      },
    );

    for (final entry in inventory.storagePathsByBucket.entries) {
      await _removeStoragePaths(entry.key, entry.value);
    }

    await client.auth.admin.deleteUser(inventory.user.id);
    return databaseResult is Map<String, dynamic>
        ? databaseResult
        : <String, dynamic>{'database_result': databaseResult};
  }

  Future<void> sendPasswordReset(String email, {String? redirectUrl}) async {
    final user = await findUserByEmail(email);
    await client.auth.resetPasswordForEmail(
      user.email!,
      redirectTo: redirectUrl,
    );
  }

  Future<void> setPassword(String email, String password) async {
    if (password.length < 12) {
      throw ArgumentError(
        'The new password must contain at least 12 characters.',
      );
    }
    final user = await findUserByEmail(email);
    await client.auth.admin.updateUserById(
      user.id,
      attributes: AdminUserAttributes(password: password),
    );
  }

  Future<List<Map<String, dynamic>>> listFeedback({String? status}) async {
    const fields =
        'id,user_id,user_email,feedback_type,comment,status,platform,'
        'app_version,current_screen,attachment_path,metadata,created_at,updated_at';
    final response = status == null
        ? await client
              .from('user_feedback')
              .select(fields)
              .order('created_at', ascending: false)
        : await client
              .from('user_feedback')
              .select(fields)
              .eq('status', status)
              .order('created_at', ascending: false);
    return response.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> getFeedback(String id) async {
    final response = await client
        .from('user_feedback')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) {
      throw StateError('No feedback was found with ID $id.');
    }
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> updateFeedbackStatus(
    String id,
    String status,
  ) async {
    const allowed = {'new', 'reviewed', 'planned', 'resolved', 'closed'};
    if (!allowed.contains(status)) {
      throw ArgumentError('Status must be one of: ${allowed.join(', ')}.');
    }
    final response = await client
        .from('user_feedback')
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<String?> feedbackAttachmentUrl(Map<String, dynamic> feedback) async {
    final path = feedback['attachment_path'];
    if (path is! String || path.isEmpty) return null;
    return client.storage
        .from('feedback-attachments')
        .createSignedUrl(path, 3600);
  }

  Future<List<Map<String, dynamic>>> _listImageRows(String dataUserId) async {
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final response = await client
          .from('image_assets')
          .select('id,user_id,user_email,storage_path,thumbnail_storage_path')
          .eq('user_id', dataUserId)
          .range(from, from + _pageSize - 1);
      final batch = response
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      rows.addAll(batch);
      if (batch.length < _pageSize) break;
      from += _pageSize;
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _listCategoryRows(
    String dataUserId,
  ) async {
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final response = await client
          .from('reference_categories')
          .select('id,user_id,code,display_name,thumbnail_asset')
          .eq('user_id', dataUserId)
          .eq('is_builtin', false)
          .range(from, from + _pageSize - 1);
      final batch = response
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      rows.addAll(batch);
      if (batch.length < _pageSize) break;
      from += _pageSize;
    }
    return rows;
  }

  Future<List<String>> _listStorageTree(String bucket, String root) async {
    final paths = <String>[];
    await _walkStorage(bucket, root, paths);
    return paths;
  }

  Future<void> _walkStorage(
    String bucket,
    String folder,
    List<String> paths,
  ) async {
    var offset = 0;
    while (true) {
      final entries = await client.storage
          .from(bucket)
          .list(
            path: folder,
            searchOptions: SearchOptions(
              limit: _storagePageSize,
              offset: offset,
              sortBy: const SortBy(column: 'name', order: 'asc'),
            ),
          );
      for (final entry in entries) {
        final path = folder.isEmpty ? entry.name : '$folder/${entry.name}';
        if (entry.id == null) {
          await _walkStorage(bucket, path, paths);
        } else {
          paths.add(path);
        }
      }
      if (entries.length < _storagePageSize) break;
      offset += _storagePageSize;
    }
  }

  Future<void> _removeStoragePaths(String bucket, List<String> paths) async {
    for (var start = 0; start < paths.length; start += 1000) {
      final end = (start + 1000 < paths.length) ? start + 1000 : paths.length;
      await client.storage.from(bucket).remove(paths.sublist(start, end));
    }
  }

  bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    final dot = value.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < value.length - 1;
  }
}
