import 'package:art_reference_app/services/maintenance_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<String> createTargetUser(TestSession session) async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final targetEmail = 'e2e-target-$suffix@example.com'.toLowerCase();
    final createdTarget = await session.admin.auth.admin.createUser(
      AdminUserAttributes(email: targetEmail, emailConfirm: true),
    );
    final targetUserId = createdTarget.user!.id;
    addTearDown(() async {
      await session.admin.auth.admin.deleteUser(targetUserId);
    });
    return targetUserId;
  }

  testWidgets(
    'admin can impersonate another user and the session actually switches',
    (tester) async {
      final adminSession = await createTestSession(
        tester,
        appMetadata: const {'is_admin': true},
      );
      final targetUserId = await createTargetUser(adminSession);
      final targetEmail =
          (await adminSession.admin.auth.admin.getUserById(
            targetUserId,
          )).user!.email!;

      final maintenance = MaintenanceService(adminSession.client);
      final adminAccessToken =
          adminSession.client.auth.currentSession!.accessToken;

      final result = await maintenance.impersonate(targetUserId);
      expect(result['email'], targetEmail);
      expect((result['token_hash'] as String).isNotEmpty, isTrue);

      await adminSession.client.auth.verifyOTP(
        type: OtpType.magiclink,
        tokenHash: result['token_hash'] as String,
      );

      final impersonatedSession = adminSession.client.auth.currentSession;
      expect(impersonatedSession, isNotNull);
      expect(impersonatedSession!.user.id, targetUserId);
      expect(impersonatedSession.user.email, targetEmail);
      expect(impersonatedSession.accessToken, isNot(adminAccessToken));
    },
  );

  testWidgets('non-admin users are rejected when attempting to impersonate', (
    tester,
  ) async {
    final session = await createTestSession(tester);
    final targetUserId = await createTargetUser(session);

    final maintenance = MaintenanceService(session.client);
    await expectLater(
      maintenance.impersonate(targetUserId),
      throwsA(isA<FunctionException>()),
    );
  });

  testWidgets('admins cannot impersonate their own account', (tester) async {
    final adminSession = await createTestSession(
      tester,
      appMetadata: const {'is_admin': true},
    );
    final adminUserId = adminSession.client.auth.currentUser!.id;

    final maintenance = MaintenanceService(adminSession.client);
    await expectLater(
      maintenance.impersonate(adminUserId),
      throwsA(isA<FunctionException>()),
    );
  });
}
