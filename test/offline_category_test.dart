import 'dart:convert';
import 'package:art_reference_app/models/reference_category.dart';
import 'package:art_reference_app/screens/category_screen.dart';
import 'package:art_reference_app/services/local_user_session.dart';
import 'package:art_reference_app/services/network_availability.dart';
import 'package:art_reference_app/services/offline_upload_queue.dart';
import 'package:art_reference_app/services/user_activity_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'new offline photo appears in an uncached category and survives reopening',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'last_authenticated_user_v1': jsonEncode({
          'user_id': 'a',
          'email': 'a@example.com',
        }),
      });
      await LocalUserSession.initialize();
      LocalUserSession.activateOffline('a@example.com');
      ConnectivityMonitor.instance.setForTesting(
        BackendConnectivityState.noInternet,
      );
      UserActivityLogger.instance.sink = (_) async {};
      final queue = OfflineUploadQueue(
        factory: idbFactoryMemory,
        databaseName: 'category-test',
      );
      const category = ReferenceCategory(
        id: 1,
        databaseCode: 'animals',
        displayName: 'Animals',
        isBuiltIn: true,
      );

      Widget screen() => MaterialApp(
        home: CategoryScreen(category: category, uploadQueue: queue),
      );
      await tester.runAsync(() async {
        await queue.enqueue(
          userId: 'a',
          userEmail: 'a@example.com',
          category: category,
          imageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHZkAAAAASUVORK5CYII=',
          ),
          originalFilename: 'new.png',
        );
      });
      await tester.pumpWidget(screen());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved offline'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Unable to load photo references.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved offline'), findsOneWidget);
      expect(find.text('Unable to load photo references.'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => queue.close());
      UserActivityLogger.instance.sink = null;
    },
  );
}
