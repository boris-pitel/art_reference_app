import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/screens/image_details_screen.dart';
import 'package:art_reference_app/services/category_service.dart';
import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'autosaves title, notes, author, and favorite after the debounce window',
    (tester) async {
      final session = await createTestSession(tester);
      final assets = ImageAssetService(session.client);
      final categories = await CategoryService(session.client).listCategories();
      final portrait = categories.firstWhere(
        (category) => category.databaseCode == 'portrait',
      );
      final image = await uploadAndFind(
        assets,
        portrait,
        uniqueImageBytes(seed: 10),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ImageDetailsScreen(
            imageId: image.id,
            imageUrl: image.imageUrl,
            dateAdded: image.dateAdded,
          ),
        ),
      );
      await pumpUntil(tester, find.text('Image Details'));
      await pumpUntil(tester, find.widgetWithText(TextField, 'Notes'));

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Autosaved Title',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'Autosaved notes about this reference.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Author'),
        'Autosaved Author',
      );
      // Toggle favorite via the always-on-screen AppBar icon rather than the
      // SwitchListTile further down the ListView, which can land under the
      // AppBar after a scroll on a short viewport.
      await tester.tap(find.byTooltip('Add to favorites'));
      await tester.pump();

      // The screen debounces saves by 1200ms; wait past that, then poll the
      // real backend until the change lands (or fail on timeout).
      Map<String, dynamic> metadata = {};
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await tester.pump();
        metadata = await fetchImageMetadata(
          session.client,
          session.dataUserId,
          image.id,
        );
        if (metadata['title'] == 'Autosaved Title') break;
      }

      expect(metadata['title'], 'Autosaved Title');
      expect(metadata['notes'], 'Autosaved notes about this reference.');
      expect(metadata['source_url'], 'Autosaved Author');
      expect(metadata['is_favorite'], isTrue);
    },
  );

  testWidgets('saves immediately when leaving via the home button', (
    tester,
  ) async {
    final session = await createTestSession(tester);
    final assets = ImageAssetService(session.client);
    final categories = await CategoryService(session.client).listCategories();
    final stillLife = categories.firstWhere(
      (category) => category.databaseCode == 'still_life',
    );
    final image = await uploadAndFind(
      assets,
      stillLife,
      uniqueImageBytes(seed: 11),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ImageDetailsScreen(
          imageId: image.id,
          imageUrl: image.imageUrl,
          dateAdded: image.dateAdded,
        ),
      ),
    );
    await pumpUntil(tester, find.text('Image Details'));
    await pumpUntil(tester, find.widgetWithText(TextField, 'Notes'));

    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'Saved on exit.',
    );
    await tester.pump();

    // Tapping Home triggers an explicit save before navigating, well before
    // the 1200ms autosave debounce would otherwise fire.
    await tester.tap(find.byTooltip('Home — Categories'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final metadata = await fetchImageMetadata(
      session.client,
      session.dataUserId,
      image.id,
    );
    expect(metadata['notes'], 'Saved on exit.');
  });

  testWidgets('moves an image between categories', (tester) async {
    final session = await createTestSession(tester);
    final assets = ImageAssetService(session.client);
    final categories = await CategoryService(session.client).listCategories();
    final landscape = categories.firstWhere(
      (category) => category.databaseCode == 'landscape',
    );
    final stillLife = categories.firstWhere(
      (category) => category.databaseCode == 'still_life',
    );
    final image = await uploadAndFind(
      assets,
      landscape,
      uniqueImageBytes(seed: 12),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ImageDetailsScreen(
          imageId: image.id,
          imageUrl: image.imageUrl,
          dateAdded: image.dateAdded,
        ),
      ),
    );
    await pumpUntil(tester, find.text('Image Details'));
    await pumpUntil(tester, find.widgetWithText(TextField, 'Notes'));

    await tester.tap(find.byTooltip('Image actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move...'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Move Reference'));

    await tester.tap(
      find.byType(DropdownButtonFormField<ReferenceCategory>).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Still Life').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Move'));
    await pumpUntil(tester, find.textContaining('Image moved to Still Life'));

    final landscapeImages = await assets.listImages(landscape);
    final stillLifeImages = await assets.listImages(stillLife);
    expect(landscapeImages.map((item) => item.id), isNot(contains(image.id)));
    expect(stillLifeImages.map((item) => item.id), contains(image.id));
  });

  testWidgets('creates a sketch and then edits it, saving each version', (
    tester,
  ) async {
    final session = await createTestSession(tester);
    final assets = ImageAssetService(session.client);
    final categories = await CategoryService(session.client).listCategories();
    final portrait = categories.firstWhere(
      (category) => category.databaseCode == 'portrait',
    );
    final parent = await uploadAndFind(
      assets,
      portrait,
      uniqueImageBytes(seed: 13),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ImageDetailsScreen(
          imageId: parent.id,
          imageUrl: parent.imageUrl,
          dateAdded: parent.dateAdded,
        ),
      ),
    );
    await pumpUntil(tester, find.text('Image Details'));
    await pumpUntil(tester, find.widgetWithText(TextField, 'Notes'));

    // --- Create a sketch from the parent image ---
    final hero = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'main-image-${parent.id}',
    );
    await pumpUntil(tester, hero);
    await tester.tap(hero);
    await tester.pumpAndSettle();

    expect(find.text('Edit sketch'), findsOneWidget);
    expect(find.text('Save as sketch'), findsOneWidget);
    await tester.tap(find.text('Edit sketch'));
    await pumpUntil(tester, find.text('Rotate 90°'));

    await tester.tap(find.text('Rotate 90°'));
    await tester.pump();
    await tester.tap(find.text('Save'));

    // Sketch creation auto-returns to Image Details once the upload lands
    // (no snackbar for creation, unlike editing an existing sketch).
    await pumpUntil(
      tester,
      find.text('Image Details'),
      timeout: const Duration(seconds: 45),
    );
    await pumpUntil(tester, find.widgetWithText(TextField, 'Notes'));

    final firstChildren = await assets.listAssociatedImages(parent.id);
    expect(firstChildren, hasLength(1));
    final originalChild = firstChildren.single;

    // --- Open the created sketch and edit it ---
    final originalTile = find.byKey(
      ValueKey('associated-image-${originalChild.id}'),
    );
    await tester.scrollUntilVisible(
      originalTile,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await pumpUntil(tester, originalTile);
    await tester.tap(originalTile);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Associated Image Details'));
    await pumpUntil(tester, find.widgetWithText(TextField, 'Notes'));

    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Edit sketch'));
    expect(find.text('Save as sketch'), findsNothing);
    await tester.tap(find.text('Edit sketch'));
    await pumpUntil(tester, find.text('Rotate 90°'));

    await tester.tap(find.text('Rotate 90°'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await pumpUntil(
      tester,
      find.text('Sketch updated.'),
      timeout: const Duration(seconds: 45),
    );

    await tester.tap(find.byTooltip('Back').last);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Associated Image Details'));
    await tester.tap(find.byTooltip('Back').last);
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Image Details'));

    final refreshedChildren = await assets.listAssociatedImages(parent.id);
    expect(refreshedChildren, hasLength(1));
    expect(refreshedChildren.single.id, isNot(originalChild.id));
  });
}
