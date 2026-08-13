import 'package:art_reference_app/screens/conversation_screen.dart';
import 'package:art_reference_app/services/messaging_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_support.dart';

/// Messaging tests need two users signed in *at the same time*, but
/// [createTestSession] signs in on the shared `Supabase.instance.client`
/// singleton — a second call would just sign the first user back out on the
/// same client. This creates an independent client (own socket, own
/// session) for the second party, while the first party keeps using the
/// singleton so it can still drive widget pumps.
Future<TestSession> createSecondPartySession(
  WidgetTester tester, {
  required String loginName,
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
  final email = 'e2e-second-${suffix}_${identityHashCode(tester)}@example.com'
      .toLowerCase();
  final password = 'E2ePainter-$suffix!';

  final createdUser = await admin.auth.admin.createUser(
    AdminUserAttributes(
      email: email,
      password: password,
      emailConfirm: true,
      userMetadata: {'login_name': loginName},
    ),
  );

  final client = SupabaseClient(
    url,
    publishableKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  await client.auth.signInWithPassword(email: email, password: password);

  final session = TestSession(client: client, admin: admin, email: email);

  addTearDown(() async {
    await client.auth.signOut();
    client.dispose();
    await admin.auth.admin.deleteUser(createdUser.user!.id);
    admin.dispose();
  });

  return session;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'sends text and image messages that the recipient can see and read',
    (tester) async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final userA = await createTestSession(tester, loginName: 'e2ea$suffix');
      final userB = await createSecondPartySession(
        tester,
        loginName: 'e2eb$suffix',
      );

      final servicesA = MessagingService(userA.client);
      final servicesB = MessagingService(userB.client);

      final found = await servicesA.searchUsers('e2eb$suffix');
      expect(found, hasLength(1));
      expect(found.single.loginName, 'e2eb$suffix');
      final bUserId = found.single.id;

      await servicesA.sendMessage(recipientId: bUserId, body: 'Hello from A!');

      final prepared = await servicesA.prepareImageUpload();
      await servicesA.uploadMessageImageBytes(
        uniqueImageBytes(seed: 21),
        prepared,
      );
      await servicesA.sendMessage(
        recipientId: bUserId,
        imageStoragePath: prepared.storagePath,
      );

      final bConversations = await servicesB.listConversations();
      expect(bConversations, hasLength(1));
      final conversation = bConversations.single;
      expect(conversation.unreadCount, 2);

      final bMessages = await servicesB.listMessages(conversation.conversationId);
      expect(bMessages, hasLength(2));
      expect(bMessages.every((m) => !m.isMine), isTrue);
      expect(bMessages[0].body, 'Hello from A!');
      expect(bMessages[1].imageUrl, isNotNull);

      // Widget-level check: ConversationScreen always reads
      // Supabase.instance.client, which is signed in as A (the singleton)
      // in this test process, so pump it as A viewing the thread with B.
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            conversationId: conversation.conversationId,
            otherUserId: bUserId,
            otherLoginName: 'e2eb$suffix',
          ),
        ),
      );
      await pumpUntil(tester, find.text('Hello from A!'));
      await pumpUntil(tester, find.byType(Image));

      await servicesB.markConversationRead(conversation.conversationId);
      final afterRead = await servicesB.listConversations();
      expect(afterRead.single.unreadCount, 0);
    },
  );

  testWidgets('discoverability opt-out hides a user from search', (
    tester,
  ) async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final userA = await createTestSession(tester, loginName: 'e2ec$suffix');
    final userB = await createSecondPartySession(
      tester,
      loginName: 'e2ed$suffix',
    );

    final servicesA = MessagingService(userA.client);
    final servicesB = MessagingService(userB.client);

    final visible = await servicesA.searchUsers('e2ed$suffix');
    expect(visible, hasLength(1));

    await servicesB.setDiscoverable(false);

    final hidden = await servicesA.searchUsers('e2ed$suffix');
    expect(hidden, isEmpty);
  });

  testWidgets(
    'blocking rejects sends with an explicit error and hides both users from search; unblocking restores it',
    (tester) async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final userA = await createTestSession(tester, loginName: 'e2ee$suffix');
      final userB = await createSecondPartySession(
        tester,
        loginName: 'e2ef$suffix',
      );

      final servicesA = MessagingService(userA.client);
      final servicesB = MessagingService(userB.client);

      final bFound = await servicesA.searchUsers('e2ef$suffix');
      final bUserId = bFound.single.id;
      final aFound = await servicesB.searchUsers('e2ee$suffix');
      final aUserId = aFound.single.id;

      await servicesA.blockUser(bUserId);

      final hiddenFromA = await servicesA.searchUsers('e2ef$suffix');
      expect(hiddenFromA, isEmpty);
      final hiddenFromB = await servicesB.searchUsers('e2ee$suffix');
      expect(hiddenFromB, isEmpty);

      await expectLater(
        servicesB.sendMessage(recipientId: aUserId, body: 'Can you see this?'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains("blocked"),
          ),
        ),
      );

      await servicesA.unblockUser(bUserId);

      final visibleAgain = await servicesA.searchUsers('e2ef$suffix');
      expect(visibleAgain, hasLength(1));

      final sendResult = await servicesB.sendMessage(
        recipientId: aUserId,
        body: 'Now it should work.',
      );
      expect(sendResult.messageId, isNotEmpty);
    },
  );
}
