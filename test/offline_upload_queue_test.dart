import 'dart:io';
import 'dart:typed_data';

import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/services/offline_upload_queue.dart';
import 'package:art_reference_app/services/user_activity_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'queued originals survive reopening and remain isolated by user and category',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'offline_upload_test',
      );
      final factory = getIdbFactoryPersistent(directory.path);
      var queue = OfflineUploadQueue(factory: factory, databaseName: 'queue');
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
      queue = OfflineUploadQueue(factory: factory, databaseName: 'queue');
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
}
