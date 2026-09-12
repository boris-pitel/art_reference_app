import 'dart:io';
import 'dart:typed_data';

import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/services/offline_upload_queue.dart';
import 'package:art_reference_app/services/user_activity_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_io.dart';
import 'package:idb_shim/idb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'queued originals survive reopening and remain isolated by user and category',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'offline_upload_test',
      );
      final factory = getIdbFactoryPersistent(directory.path);
      var queue = OfflineUploadQueue(
        factory: factory,
        databaseName: 'queue',
        originalDirectory: directory.path,
      );
      UserActivityLogger.instance.sink = (_) async {};
      addTearDown(() async {
        await queue.close();
        UserActivityLogger.instance.sink = null;
        await directory.delete(recursive: true);
      });
      const inbox = ReferenceCategory(
        id: 0,
        databaseCode: 'inbox',
        displayName: 'Inbox',
        isBuiltIn: true,
      );
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final first = await queue.enqueue(
        userId: 'a',
        userEmail: 'A@example.com',
        category: inbox,
        imageBytes: bytes,
        originalFilename: 'original.heic',
      );
      await queue.enqueue(
        userId: 'b',
        userEmail: 'b@example.com',
        category: inbox,
        imageBytes: bytes,
      );
      await queue.close();
      queue = OfflineUploadQueue(
        factory: factory,
        databaseName: 'queue',
        originalDirectory: directory.path,
      );
      final restored = await queue.listForUser('a', categoryCode: 'inbox');
      expect(restored, hasLength(1));
      expect(restored.single.id, first.id);
      expect(restored.single.imageBytes, orderedEquals(bytes));
      expect(restored.single.originalFilename, 'original.heic');
      expect(restored.single.userEmail, 'a@example.com');
      expect(await queue.listForUser('a', categoryCode: 'other'), isEmpty);
      await queue.clearForUser('a');
      expect(await queue.listForUser('a'), isEmpty);
      expect(await queue.listForUser('b'), hasLength(1));
    },
  );
  test(
    'queue summaries omit originals and legacy v1 records migrate without loss',
    () async {
      final factory = idbFactoryMemory;
      final db = await factory.open(
        'legacy',
        version: 1,
        onUpgradeNeeded: (event) {
          event.database.createObjectStore('pending_uploads', keyPath: 'id');
        },
      );
      final original = Uint8List.fromList(
        List.generate(1024 * 1024, (i) => i % 256),
      );
      final tx = db.transaction('pending_uploads', idbModeReadWrite);
      await tx
          .objectStore('pending_uploads')
          .put(
            PendingImageUpload(
              id: 'legacy-photo',
              userId: 'a',
              userEmail: 'a@example.com',
              categoryCode: 'inbox',
              categoryName: 'Inbox',
              categoryIsBuiltIn: true,
              imageBytes: original,
              previewBytes: Uint8List.fromList([1]),
              createdAt: DateTime.utc(2026),
            ).toRecord(),
          );
      await tx.completed;
      db.close();
      final queue = OfflineUploadQueue(
        factory: factory,
        databaseName: 'legacy',
      );
      addTearDown(queue.close);
      final summaries = await queue.listForUser('a', includeOriginals: false);
      expect(summaries, hasLength(1));
      expect(summaries.single.imageBytes, isEmpty);
      expect(
        await queue.originalBytes(summaries.single),
        orderedEquals(original),
      );
      await queue.remove('legacy-photo');
      expect(await queue.listForUser('a', includeOriginals: false), isEmpty);
    },
  );
}
