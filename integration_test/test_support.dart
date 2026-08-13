import 'dart:io';
import 'dart:typed_data';

import 'package:art_reference_app/services/image_asset_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

Map<String, String> readEnvironmentFile(String path) {
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

/// A signed-in ephemeral Supabase user for e2e tests, with a teardown
/// that deletes every trace of it (data rows, storage objects, auth user).
class TestSession {
  const TestSession({
    required this.client,
    required this.admin,
    required this.email,
  });

  final SupabaseClient client;
  final SupabaseClient admin;
  final String email;

  String get dataUserId =>
      const Uuid().v5(Namespace.url.value, 'art-reference-user:$email');
}

Future<TestSession> createTestSession(
  WidgetTester tester, {
  String? loginName,
}) async {
  final publicConfig = readEnvironmentFile('env');
  final adminConfig = readEnvironmentFile('.env.admin');
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
  final email = 'e2e-${suffix}_${identityHashCode(tester)}@example.com'
      .toLowerCase();
  final password = 'E2ePainter-$suffix!';

  final createdUser = await admin.auth.admin.createUser(
    AdminUserAttributes(
      email: email,
      password: password,
      emailConfirm: true,
      userMetadata: loginName == null ? null : {'login_name': loginName},
    ),
  );

  await Supabase.initialize(url: url, publishableKey: publishableKey);
  final client = Supabase.instance.client;
  await client.auth.signInWithPassword(email: email, password: password);

  final session = TestSession(client: client, admin: admin, email: email);

  addTearDown(() async {
    await client.auth.signOut();
    final dataUserId = session.dataUserId;
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

  return session;
}

/// Generates a small, uniquely-colored JPEG so repeated calls never collide
/// on the server's content-hash dedup check.
Uint8List uniqueImageBytes({int seed = 0}) {
  final image = img.Image(width: 180, height: 120);
  final r = 30 + (seed * 53) % 200;
  final g = 60 + (seed * 97) % 180;
  final b = 90 + (seed * 149) % 150;
  img.fill(image, color: img.ColorRgb8(r, g, b));
  img.drawLine(
    image,
    x1: 10,
    y1: 20 + seed % 60,
    x2: 170,
    y2: 100 - seed % 60,
    color: img.ColorRgb8(255 - r, 255 - g, 255 - b),
    thickness: 4,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

Future<void> pumpUntil(
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

Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(finder, findsNothing);
}

Future<Map<String, dynamic>> fetchImageMetadata(
  SupabaseClient client,
  String userId,
  String imageId,
) async {
  final response = await client.functions.invoke(
    'get-image-metadata',
    method: HttpMethod.get,
    headers: {'x-user-id': userId, 'x-image-id': imageId},
  );
  return Map<String, dynamic>.from(response.data as Map);
}

Future<ImageAssetInfo> uploadAndFind(
  ImageAssetService service,
  dynamic category,
  Uint8List bytes,
) async {
  final id = await service.uploadImage(bytes, category);
  final images = await service.listImages(category);
  return images.firstWhere((item) => item.id == id);
}
