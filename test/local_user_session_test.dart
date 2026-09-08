import 'dart:convert';

import 'package:art_reference_app/services/local_user_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('opens only the remembered user library offline', () async {
    SharedPreferences.setMockInitialValues({
      'last_authenticated_user_v1': jsonEncode({
        'user_id': 'user-a',
        'email': 'person@example.com',
      }),
    });
    await LocalUserSession.initialize();

    expect(LocalUserSession.activateOffline('PERSON@example.com'), isTrue);
    expect(LocalUserSession.effectiveUserId, 'user-a');
    expect(LocalUserSession.effectiveEmail, 'person@example.com');
  });

  test('refuses an email that does not own the saved library', () async {
    SharedPreferences.setMockInitialValues({
      'last_authenticated_user_v1': jsonEncode({
        'user_id': 'user-a',
        'email': 'person@example.com',
      }),
    });
    await LocalUserSession.initialize();

    expect(LocalUserSession.activateOffline('other@example.com'), isFalse);
    expect(LocalUserSession.effectiveUserId, isNull);
  });

  test('first login cannot be performed offline', () async {
    await LocalUserSession.initialize();

    expect(LocalUserSession.activateOffline('new@example.com'), isFalse);
    expect(LocalUserSession.rememberedUser, isNull);
  });
}
