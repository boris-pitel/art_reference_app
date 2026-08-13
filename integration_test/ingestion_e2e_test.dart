import 'dart:typed_data';

import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/screens/category_screen.dart';
import 'package:art_reference_app/services/category_service.dart';
import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<ReferenceCategory> inboxCategory(SupabaseClient client) async {
    final categories = await CategoryService(client).listCategories();
    return categories.firstWhere((category) => category.isInbox);
  }

  testWidgets('ingests images into Inbox and renders them in the grid', (
    tester,
  ) async {
    final session = await createTestSession(tester);
    final assets = ImageAssetService(session.client);
    final inbox = await inboxCategory(session.client);

    final firstId = await assets.uploadImage(uniqueImageBytes(seed: 1), inbox);
    final secondId = await assets.uploadImage(
      uniqueImageBytes(seed: 2),
      inbox,
    );

    // The ingestion pipeline (hash, upload, thumbnail, finalize) really ran
    // against the backend, so the listing endpoint must see both images.
    final listed = await assets.listImages(inbox);
    expect(listed.map((item) => item.id), containsAll([firstId, secondId]));

    await tester.pumpWidget(
      MaterialApp(home: CategoryScreen(category: inbox)),
    );
    await pumpUntil(tester, find.text('Inbox'));
    await pumpUntilGone(tester, find.byType(CircularProgressIndicator));

    expect(find.text('No photo references yet.'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets(
    'rejects a same-category duplicate but links an existing image into a new category without re-uploading',
    (tester) async {
      final session = await createTestSession(tester);
      final assets = ImageAssetService(session.client);
      final categories = await CategoryService(session.client).listCategories();
      final inbox = categories.firstWhere((category) => category.isInbox);
      final portrait = categories.firstWhere(
        (category) => category.databaseCode == 'portrait',
      );

      final bytes = uniqueImageBytes(seed: 7);
      final originalId = await assets.uploadImage(bytes, inbox);

      // Re-adding identical bytes to the same category must not silently
      // succeed as a second entry.
      await expectLater(
        assets.uploadImage(bytes, inbox),
        throwsA(
          isA<FunctionException>().having(
            (error) => error.status,
            'status',
            409,
          ),
        ),
      );
      final inboxAfterDuplicate = await assets.listImages(inbox);
      expect(inboxAfterDuplicate.where((item) => item.id == originalId), hasLength(1));

      // The same bytes added to a *different* category should reuse the
      // already-uploaded original instead of storing a second physical copy.
      final linkedId = await assets.uploadImage(bytes, portrait);
      expect(linkedId, originalId);
      final portraitImages = await assets.listImages(portrait);
      expect(portraitImages.map((item) => item.id), contains(originalId));
    },
  );

  testWidgets('rejects unsupported image data with a clear error', (
    tester,
  ) async {
    final session = await createTestSession(tester);
    final assets = ImageAssetService(session.client);
    final inbox = await inboxCategory(session.client);

    await expectLater(
      assets.uploadImage(
        Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]),
        inbox,
      ),
      throwsA(isA<UnsupportedImageFormatException>()),
    );

    final listed = await assets.listImages(inbox);
    expect(listed, isEmpty);
  });

  testWidgets(
    'removing an image from a category updates the grid immediately',
    (tester) async {
      final session = await createTestSession(tester);
      final assets = ImageAssetService(session.client);
      final inbox = await inboxCategory(session.client);

      await assets.uploadImage(uniqueImageBytes(seed: 3), inbox);

      await tester.pumpWidget(
        MaterialApp(home: CategoryScreen(category: inbox)),
      );
      await pumpUntil(tester, find.text('Inbox'));
      await pumpUntilGone(tester, find.byType(CircularProgressIndicator));
      expect(find.byType(Image), findsOneWidget);

      await tester.longPress(find.byType(Image).first);
      await tester.pumpAndSettle();
      await pumpUntil(tester, find.text('Remove'));
      // The action sheet scrolls now that it has more items than fit on a
      // short test window; ensureVisible finds the real render offset
      // (unlike scrollUntilVisible, which no-ops when the target already
      // exists in the tree but is merely scrolled out of the viewport).
      await tester.ensureVisible(find.text('Remove'));
      await tester.pump();
      await tester.tap(find.text('Remove'));
      await pumpUntil(tester, find.text('Reference removed.'));

      final listed = await assets.listImages(inbox);
      expect(listed, isEmpty);
    },
  );
}
