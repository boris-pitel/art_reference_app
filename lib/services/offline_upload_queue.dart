import 'package:flutter/foundation.dart';
import 'package:idb_shim/idb.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/reference_category.dart';
import 'image_asset_service.dart';
import 'image_import_service.dart';
import 'network_availability.dart';
import 'offline_upload_database_factory.dart';
import 'thumbnail_service.dart';
import 'user_activity_logger.dart';

class PendingImageUpload {
  const PendingImageUpload({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.categoryCode,
    required this.categoryName,
    required this.categoryIsBuiltIn,
    required this.imageBytes,
    required this.previewBytes,
    required this.createdAt,
    this.originalFilename,
    this.lastError,
  });

  final String id;
  final String userId;
  final String userEmail;
  final String categoryCode;
  final String categoryName;
  final bool categoryIsBuiltIn;
  final Uint8List imageBytes;
  final Uint8List previewBytes;
  final DateTime createdAt;
  final String? originalFilename;
  final String? lastError;

  ReferenceCategory get category => ReferenceCategory(
    id: 0,
    databaseCode: categoryCode,
    displayName: categoryName,
    isBuiltIn: categoryIsBuiltIn,
    userId: userId,
  );

  PendingImageUpload copyWith({String? lastError}) => PendingImageUpload(
    id: id,
    userId: userId,
    userEmail: userEmail,
    categoryCode: categoryCode,
    categoryName: categoryName,
    categoryIsBuiltIn: categoryIsBuiltIn,
    imageBytes: imageBytes,
    previewBytes: previewBytes,
    createdAt: createdAt,
    originalFilename: originalFilename,
    lastError: lastError,
  );

  Map<String, Object?> toRecord() => {
    'id': id,
    'user_id': userId,
    'user_email': userEmail,
    'category_code': categoryCode,
    'category_name': categoryName,
    'category_is_builtin': categoryIsBuiltIn,
    'image_bytes': imageBytes,
    'preview_bytes': previewBytes,
    'created_at': createdAt.toUtc().toIso8601String(),
    'original_filename': originalFilename,
    'last_error': lastError,
  };

  factory PendingImageUpload.fromRecord(Object value) {
    if (value is! Map) {
      throw const FormatException('Pending upload record is not a map.');
    }
    final record = Map<String, dynamic>.from(value);
    Uint8List readBytes(String key) {
      final bytes = record[key];
      if (bytes is Uint8List) return bytes;
      if (bytes is List) return Uint8List.fromList(bytes.cast<int>());
      throw FormatException('Pending upload has no $key.');
    }

    return PendingImageUpload(
      id: record['id'] as String,
      userId: record['user_id'] as String,
      userEmail: record['user_email'] as String,
      categoryCode: record['category_code'] as String,
      categoryName: record['category_name'] as String,
      categoryIsBuiltIn: record['category_is_builtin'] == true,
      imageBytes: readBytes('image_bytes'),
      previewBytes: readBytes('preview_bytes'),
      createdAt: DateTime.parse(record['created_at'] as String),
      originalFilename: record['original_filename'] as String?,
      lastError: record['last_error'] as String?,
    );
  }
}

class OfflineUploadSyncResult {
  const OfflineUploadSyncResult({
    required this.uploaded,
    required this.failed,
    required this.remaining,
  });

  final int uploaded;
  final int failed;
  final int remaining;
}

/// Durable per-user queue for new images selected while the app is offline.
///
/// Existing server records are never edited here. A queued upload only adds a
/// new immutable image, which avoids the cross-device merge problem that makes
/// general offline editing unsafe.
class OfflineUploadQueue extends ChangeNotifier {
  OfflineUploadQueue({IdbFactory? factory, String? databaseName})
    : _factoryOverride = factory,
      _databaseName = databaseName ?? 'painter_reference_offline_uploads';

  static final OfflineUploadQueue instance = OfflineUploadQueue();

  static const String _storeName = 'pending_uploads';
  final IdbFactory? _factoryOverride;
  final String _databaseName;
  Future<Database>? _databaseFuture;
  Future<OfflineUploadSyncResult>? _activeSync;

  Future<Database> _database() {
    return _databaseFuture ??= _openDatabase();
  }

  Future<Database> _openDatabase() async {
    final factory =
        _factoryOverride ?? await createOfflineUploadDatabaseFactory();
    return factory.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        if (!event.database.objectStoreNames.contains(_storeName)) {
          event.database.createObjectStore(_storeName, keyPath: 'id');
        }
      },
    );
  }

  Future<PendingImageUpload> enqueue({
    required String userId,
    required String userEmail,
    required ReferenceCategory category,
    required Uint8List imageBytes,
    String? originalFilename,
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'Image is empty.');
    }

    Uint8List previewBytes = imageBytes;
    try {
      final normalized = await ImageImportService.normalizeForUpload(
        imageBytes,
      );
      previewBytes = (await ThumbnailService.createDerivatives(
        normalized,
      )).thumbnailBytes;
    } catch (_) {
      // The original is retained for the real upload. A missing preview must
      // not turn an otherwise valid offline selection into lost work.
    }

    final pending = PendingImageUpload(
      id: const Uuid().v4(),
      userId: userId,
      userEmail: userEmail.trim().toLowerCase(),
      categoryCode: category.databaseCode,
      categoryName: category.displayName,
      categoryIsBuiltIn: category.isBuiltIn,
      imageBytes: imageBytes,
      previewBytes: previewBytes,
      createdAt: DateTime.now().toUtc(),
      originalFilename: originalFilename,
    );
    await _put(pending);
    notifyListeners();
    UserActivityLogger.instance.record(
      operation: 'image_upload_queued',
      status: 'succeeded',
      targetType: 'image',
      targetId: pending.id,
      details: {
        'category': category.databaseCode,
        'bytes': imageBytes.lengthInBytes,
      },
    );
    return pending;
  }

  Future<List<PendingImageUpload>> listForUser(
    String userId, {
    String? categoryCode,
  }) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadOnly);
    final records = await transaction.objectStore(_storeName).getAll();
    await transaction.completed;
    final pending = <PendingImageUpload>[];
    for (final record in records) {
      try {
        final item = PendingImageUpload.fromRecord(record);
        if (item.userId == userId &&
            (categoryCode == null || item.categoryCode == categoryCode)) {
          pending.add(item);
        }
      } catch (error) {
        debugPrint('Ignoring an invalid pending upload record: $error');
      }
    }
    pending.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return pending;
  }

  Future<void> remove(String id) async {
    await _delete(id);
    notifyListeners();
  }

  Future<void> clearForUser(String userId) async {
    for (final pending in await listForUser(userId)) {
      await _delete(pending.id);
    }
    notifyListeners();
  }

  Future<OfflineUploadSyncResult> syncForCurrentUser(SupabaseClient supabase) {
    final running = _activeSync;
    if (running != null) return running;
    final future = _syncForCurrentUser(supabase);
    _activeSync = future;
    return future.whenComplete(() {
      if (identical(_activeSync, future)) _activeSync = null;
    });
  }

  Future<OfflineUploadSyncResult> _syncForCurrentUser(
    SupabaseClient supabase,
  ) async {
    final user = supabase.auth.currentUser;
    final email = user?.email?.trim().toLowerCase();
    if (user == null || email == null || email.isEmpty) {
      return const OfflineUploadSyncResult(
        uploaded: 0,
        failed: 0,
        remaining: 0,
      );
    }

    final pending = await listForUser(user.id);
    var uploaded = 0;
    var failed = 0;
    for (final item in pending) {
      if (supabase.auth.currentUser?.id != user.id ||
          supabase.auth.currentSession == null) {
        break;
      }
      if (ConnectivityMonitor.instance.state !=
          BackendConnectivityState.online) {
        break;
      }
      try {
        await ImageAssetService(supabase).uploadImage(
          item.imageBytes,
          item.category,
          originalFilename: item.originalFilename,
        );
        await _delete(item.id);
        uploaded++;
      } catch (error) {
        if (ImageAssetService.isDuplicateRejection(error)) {
          await _delete(item.id);
          uploaded++;
          continue;
        }
        if (NetworkAvailability.isNetworkFailure(error)) {
          ConnectivityMonitor.instance.reportBackendFailure(error);
          break;
        }
        failed++;
        await _put(item.copyWith(lastError: error.toString()));
      }
    }

    final remaining = (await listForUser(user.id)).length;
    if (uploaded > 0 || failed > 0) notifyListeners();
    return OfflineUploadSyncResult(
      uploaded: uploaded,
      failed: failed,
      remaining: remaining,
    );
  }

  Future<void> _put(PendingImageUpload pending) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    await transaction.objectStore(_storeName).put(pending.toRecord());
    await transaction.completed;
  }

  Future<void> _delete(String id) async {
    final db = await _database();
    final transaction = db.transaction(_storeName, idbModeReadWrite);
    await transaction.objectStore(_storeName).delete(id);
    await transaction.completed;
  }

  @visibleForTesting
  Future<void> close() async {
    final future = _databaseFuture;
    if (future != null) (await future).close();
    _databaseFuture = null;
  }
}
