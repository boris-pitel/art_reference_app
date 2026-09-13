import 'pending_original_store.dart';
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
    this.externalOriginal = false,
    this.parentImageId,
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
  final bool externalOriginal;
  final String? parentImageId;
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
    externalOriginal: externalOriginal,
    parentImageId: parentImageId,
    lastError: lastError,
  );

  Map<String, Object?> toRecord() => {
    'external_original': externalOriginal,
    'parent_image_id': parentImageId,
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
      externalOriginal: record['external_original'] == true,
      parentImageId: record['parent_image_id'] as String?,
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
  OfflineUploadQueue({
    IdbFactory? factory,
    String? databaseName,
    this.originalDirectory,
  }) : _factoryOverride = factory,
       _databaseName = databaseName ?? 'painter_reference_offline_uploads';

  static final OfflineUploadQueue instance = OfflineUploadQueue();

  static const String _storeName = 'pending_uploads';
  static const String _summaryStore = 'pending_summaries';
  final String? originalDirectory;
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
      version: 2,
      onUpgradeNeeded: (event) {
        if (!event.database.objectStoreNames.contains(_storeName)) {
          event.database.createObjectStore(_storeName, keyPath: 'id');
        }
        if (!event.database.objectStoreNames.contains(_summaryStore)) {
          final summaries = event.database.createObjectStore(
            _summaryStore,
            keyPath: 'id',
          );
          event.transaction
              .objectStore(_storeName)
              .openCursor(autoAdvance: true)
              .listen((cursor) {
                final record = Map<String, Object?>.from(cursor.value as Map);
                summaries.put({...record, 'image_bytes': Uint8List(0)});
              });
        }
      },
    );
  }

  int _captureSessions = 0;
  void pauseForCapture() {
    _captureSessions++;
  }

  void resumeAfterCapture() {
    if (_captureSessions > 0) _captureSessions--;
    if (_captureSessions == 0) notifyListeners();
  }

  Future<OfflineUploadSyncResult> syncAfterCapture(
    SupabaseClient supabase,
  ) async {
    final running = _activeSync;
    if (running != null) {
      try {
        await running;
      } catch (_) {}
    }
    return syncForCurrentUser(supabase);
  }

  Future<Uint8List> originalBytes(PendingImageUpload item) async {
    if (item.externalOriginal) {
      return readPendingOriginal(item.id, directoryPath: originalDirectory);
    }
    if (item.imageBytes.isNotEmpty) return item.imageBytes;
    final db = await _database();
    final tx = db.transaction(_storeName, idbModeReadOnly);
    final record = await tx.objectStore(_storeName).getObject(item.id);
    await tx.completed;
    if (record == null) throw StateError('Image has finished uploading.');
    return PendingImageUpload.fromRecord(record).imageBytes;
  }

  Future<PendingImageUpload> enqueue({
    required String userId,
    required String userEmail,
    required ReferenceCategory category,
    required Uint8List imageBytes,
    String? originalFilename,
    String? parentImageId,
    bool deferPreview = false,
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'Image is empty.');
    }

    final id = const Uuid().v4();
    final external =
        !kIsWeb && (_factoryOverride == null || originalDirectory != null);
    if (external) {
      await savePendingOriginal(
        id,
        imageBytes,
        directoryPath: originalDirectory,
      );
    }
    Uint8List previewBytes = Uint8List(0);
    try {
      if (!deferPreview) {
        final normalized = await ImageImportService.normalizeForUpload(
          imageBytes,
        );
        previewBytes = (await ThumbnailService.createDerivatives(
          normalized,
        )).thumbnailBytes;
      }
    } catch (_) {
      // The original is retained for the real upload. A missing preview must
      // not turn an otherwise valid offline selection into lost work.
    }

    final pending = PendingImageUpload(
      id: id,
      externalOriginal: external,
      parentImageId: parentImageId,
      userId: userId,
      userEmail: userEmail.trim().toLowerCase(),
      categoryCode: category.databaseCode,
      categoryName: category.displayName,
      categoryIsBuiltIn: category.isBuiltIn,
      imageBytes: external ? Uint8List(0) : imageBytes,
      previewBytes: previewBytes,
      createdAt: DateTime.now().toUtc(),
      originalFilename: originalFilename,
    );
    try {
      await _put(pending);
    } catch (_) {
      if (external) {
        await deletePendingOriginal(id, directoryPath: originalDirectory);
      }
      rethrow;
    }
    if (_captureSessions == 0) notifyListeners();
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
    bool includeOriginals = true,
  }) async {
    final db = await _database();
    final transaction = db.transaction(_summaryStore, idbModeReadOnly);
    final records = await transaction.objectStore(_summaryStore).getAll();
    await transaction.completed;
    final pending = <PendingImageUpload>[];
    for (final record in records) {
      try {
        final item = PendingImageUpload.fromRecord(record);
        if (item.userId == userId &&
            (categoryCode == null || item.categoryCode == categoryCode)) {
          if (includeOriginals) {
            pending.add(
              PendingImageUpload.fromRecord({
                ...item.toRecord(),
                'image_bytes': await originalBytes(item),
              }),
            );
          } else {
            pending.add(item);
          }
        }
      } catch (error) {
        debugPrint('Ignoring an invalid pending upload record: $error');
      }
    }
    pending.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return pending;
  }

  bool get isSyncing => _activeSync != null;
  String? _uploadingId;
  final Set<String> _removedIds = {};
  bool isUploading(String id) => _uploadingId == id;

  Future<void> remove(String id) async {
    if (isUploading(id)) {
      throw StateError(
        'This photo is uploading. Wait for it to finish before deleting.',
      );
    }
    _removedIds.add(id);
    try {
      await _delete(id);
    } catch (_) {
      _removedIds.remove(id);
      rethrow;
    }
    if (!isSyncing) _removedIds.remove(id);
    notifyListeners();
  }

  Future<void> clearForUser(String userId) async {
    for (final pending in await listForUser(userId, includeOriginals: false)) {
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
      if (identical(_activeSync, future)) {
        _activeSync = null;
        _uploadingId = null;
        _removedIds.clear();
        notifyListeners();
      }
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

    final pending = await listForUser(user.id, includeOriginals: false);
    var uploaded = 0;
    var failed = 0;
    for (final item in pending) {
      if (_removedIds.contains(item.id)) continue;
      if (_captureSessions > 0) break;
      if (supabase.auth.currentUser?.id != user.id ||
          supabase.auth.currentSession == null) {
        break;
      }
      if (ConnectivityMonitor.instance.state !=
          BackendConnectivityState.online) {
        break;
      }
      _uploadingId = item.id;
      try {
        final bytes = await originalBytes(item);
        if (item.parentImageId != null) {
          await ImageAssetService(
            supabase,
          ).uploadAssociatedImage(bytes, item.parentImageId!);
        } else {
          await ImageAssetService(supabase).uploadImage(
            bytes,
            item.category,
            originalFilename: item.originalFilename,
          );
        }
        await _delete(item.id);
        uploaded++;
        if (_captureSessions == 0) notifyListeners();
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
      } finally {
        _uploadingId = null;
      }
    }

    final remaining = (await listForUser(
      user.id,
      includeOriginals: false,
    )).length;
    if (uploaded > 0 || failed > 0) notifyListeners();
    return OfflineUploadSyncResult(
      uploaded: uploaded,
      failed: failed,
      remaining: remaining,
    );
  }

  Future<void> _put(PendingImageUpload pending) async {
    final db = await _database();
    final transaction = db.transactionList([
      _storeName,
      _summaryStore,
    ], idbModeReadWrite);
    final record = pending.toRecord();
    if (!pending.externalOriginal && pending.imageBytes.isEmpty) {
      final existing = await transaction
          .objectStore(_storeName)
          .getObject(pending.id);
      if (existing == null) throw StateError('Pending original is missing');
      record['image_bytes'] = (existing as Map)['image_bytes'];
    }
    await transaction.objectStore(_storeName).put(record);
    await transaction.objectStore(_summaryStore).put({
      ...record,
      'image_bytes': Uint8List(0),
    });
    await transaction.completed;
  }

  Future<void> _delete(String id) async {
    final db = await _database();
    final transaction = db.transactionList([
      _storeName,
      _summaryStore,
    ], idbModeReadWrite);
    await transaction.objectStore(_storeName).delete(id);
    await transaction.objectStore(_summaryStore).delete(id);
    await transaction.completed;
    if (!kIsWeb && (_factoryOverride == null || originalDirectory != null)) {
      try {
        await deletePendingOriginal(id, directoryPath: originalDirectory);
      } catch (error) {
        debugPrint('Uploaded original cleanup deferred: $error');
      }
    }
  }

  @visibleForTesting
  Future<void> close() async {
    final future = _databaseFuture;
    if (future != null) (await future).close();
    _databaseFuture = null;
  }
}
