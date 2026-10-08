import 'dart:typed_data';
import 'package:idb_shim/idb.dart';
import 'offline_upload_database_factory.dart';

class DocumentFileCache {
  DocumentFileCache({this.factory});
  static final instance = DocumentFileCache();
  final IdbFactory? factory;
  Future<Database>? _database;
  Future<Database> _db() => _database ??= _open();
  Future<Database> _open() async =>
      (factory ?? await createOfflineUploadDatabaseFactory()).open(
        'reference_documents_v1',
        version: 1,
        onUpgradeNeeded: (event) => event.database.createObjectStore('files'),
      );
  Future<void> write(String userId, String documentId, Uint8List bytes) async {
    final tx = (await _db()).transaction('files', idbModeReadWrite);
    await tx.objectStore('files').put(bytes, '$userId:$documentId');
    await tx.completed;
  }

  Future<Uint8List?> read(String userId, String documentId) async {
    final tx = (await _db()).transaction('files', idbModeReadOnly);
    final value = await tx
        .objectStore('files')
        .getObject('$userId:$documentId');
    await tx.completed;
    return value == null
        ? null
        : Uint8List.fromList(List<int>.from(value as List));
  }

  Future<void> remove(String userId, String documentId) async {
    final tx = (await _db()).transaction('files', idbModeReadWrite);
    await tx.objectStore('files').delete('$userId:$documentId');
    await tx.completed;
  }

  Future<void> clearUser(String userId) async {
    final tx = (await _db()).transaction('files', idbModeReadWrite);
    final store = tx.objectStore('files');
    final keys = await store.getAllKeys();
    for (final key in keys) {
      if (key is String && key.startsWith('$userId:')) await store.delete(key);
    }
    await tx.completed;
  }
}
