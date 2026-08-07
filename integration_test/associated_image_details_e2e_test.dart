import 'dart:io';
import 'dart:typed_data';

import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/screens/image_details_screen.dart';
import 'package:art_reference_app/services/category_service.dart';
import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

Map<String, String> _readEnvironmentFile(String path) {
  final values = <String, String>{};
  for (final rawLine in File(path).readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator).trim()] = line
        .substring(separator + 1)
        .trim();
  }
  return values;
}

Uint8List _imageBytes({required bool sketch}) {
  final image = img.Image(width: 180, height: 120);
  img.fill(
    image,
    color: sketch ? img.ColorRgb8(235, 226, 210) : img.ColorRgb8(58, 94, 130),
  );
  img.drawLine(
    image,
    x1: 10,
    y1: sketch ? 90 : 60,
    x2: 170,
    y2: sketch ? 30 : 60,
    color: sketch ? img.ColorRgb8(45, 42, 40) : img.ColorRgb8(245, 220, 160),
    thickness: 5,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsWidgets);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates a sketch without replacing the top-level image', (
    tester,
  ) async {
    final publicConfig = _readEnvironmentFile('env');
    final adminConfig = _readEnvironmentFile('.env.admin');
    final url = publicConfig['SUPABASE_URL']!;
    final publishableKey = publicConfig['SUPABASE_PUBLISHABLE_KEY']!;
    final secretKey =
        adminConfig['SUPABASE_SECRET_KEY'] ??
        adminConfig['SUPABASE_SERVICE_ROLE_KEY']!;
    final admin = SupabaseClient(
      url,
      secretKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final email = 'codex-e2e-$suffix@example.com';
    final password = 'E2ePainter-$suffix!';

    final createdUser = await admin.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    addTearDown(() async {
      await Supabase.instance.client.auth.signOut();
      final dataUserId = const Uuid().v5(
        Namespace.url.value,
        'art-reference-user:${email.toLowerCase()}',
      );
      final rows = await admin
          .from('image_assets')
          .select('storage_path,thumbnail_storage_path')
          .eq('user_id', dataUserId);
      final storagePaths = <String>{};
      for (final row in rows) {
        for (final key in ['storage_path', 'thumbnail_storage_path']) {
          final path = row[key];
          if (path is String && path.isNotEmpty) storagePaths.add(path);
        }
      }
      await admin.rpc(
        'admin_delete_user_data',
        params: {'target_user_id': dataUserId, 'target_email': email},
      );
      if (storagePaths.isNotEmpty) {
        await admin.storage
            .from('reference-images')
            .remove(storagePaths.toList());
      }
      await admin.auth.admin.deleteUser(createdUser.user!.id);
      admin.dispose();
    });

    await Supabase.initialize(url: url, publishableKey: publishableKey);
    final client = Supabase.instance.client;
    await client.auth.signInWithPassword(email: email, password: password);

    final categories = await CategoryService(client).listCategories();
    final ReferenceCategory category = categories.first;
    final assets = ImageAssetService(client);
    final parentId = await assets.uploadImage(
      _imageBytes(sketch: false),
      category,
    );
    final parent = (await assets.listImages(
      category,
    )).firstWhere((item) => item.id == parentId);

    await tester.pumpWidget(
      MaterialApp(
        home: ImageDetailsScreen(
          imageId: parent.id,
          imageUrl: parent.imageUrl,
          dateAdded: parent.dateAdded,
        ),
      ),
    );

    await _pumpUntil(tester, find.text('Image Details'));
    await _pumpUntil(tester, find.text('Notes'));
    final hero = find.byWidgetPredicate(
      (widget) => widget is Hero && widget.tag == 'main-image-$parentId',
    );
    await _pumpUntil(tester, hero);
    await tester.tap(hero);
    await tester.pumpAndSettle();

    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Create sketch'), findsOneWidget);
    await tester.tap(find.text('Create sketch'));
    await _pumpUntil(tester, find.text('Save'));
    await _pumpUntil(tester, find.text('Straighten angle'));

    expect(find.text('Straighten angle'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    final save = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    await tester.tap(find.text('Rotate 90°'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _pumpUntil(
      tester,
      find.text('Sketch created.'),
      timeout: const Duration(seconds: 45),
    );
    await _pumpUntil(tester, find.text('Image'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Image Details'), findsOneWidget);
    await _pumpUntil(tester, find.text('Notes'));
    expect(find.textContaining('Image not found'), findsNothing);
    expect(find.textContaining('Unable to load image details'), findsNothing);
    final updatedChildren = await assets.listAssociatedImages(parentId);
    expect(updatedChildren, hasLength(1));
    expect(updatedChildren.single.id, isNot(parentId));
    final originalChild = updatedChildren.single;
    final originalTile = find.byKey(
      ValueKey('associated-image-${originalChild.id}'),
    );
    await tester.scrollUntilVisible(
      originalTile,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpUntil(tester, originalTile);
    await tester.tap(originalTile);
    await _pumpUntil(tester, find.text('Associated Image Details'));
    await _pumpUntil(tester, find.text('Notes'));
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await _pumpUntil(tester, find.textContaining('Rotate 90'));
    await tester.tap(find.textContaining('Rotate 90'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _pumpUntil(
      tester,
      find.text('Sketch updated.'),
      timeout: const Duration(seconds: 45),
    );
    await tester.tap(find.byTooltip('Back').last);
    await _pumpUntil(tester, find.text('Associated Image Details'));
    await tester.tap(find.byTooltip('Back').last);
    await _pumpUntil(tester, find.text('Image Details'));

    final refreshedChildren = await assets.listAssociatedImages(parentId);
    expect(refreshedChildren, hasLength(1));
    expect(refreshedChildren.single.id, isNot(originalChild.id));
    final refreshedTile = find.byKey(
      ValueKey('associated-image-${refreshedChildren.single.id}'),
    );
    await tester.scrollUntilVisible(
      refreshedTile,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await _pumpUntil(tester, refreshedTile);
    expect(refreshedTile, findsOneWidget);
    expect(
      (await assets.listImages(category)).any((item) => item.id == parentId),
      isTrue,
    );
  });
}
