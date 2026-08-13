import 'package:art_reference_app/models/app_user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads an optional login name from a database user row', () {
    final profile = AppUserProfile.fromJson({
      'id': 'auth-user-id',
      'email': 'artist@example.com',
      'login_name': 'PainterOne',
      'is_admin': true,
    });

    expect(profile.authUserId, 'auth-user-id');
    expect(profile.email, 'artist@example.com');
    expect(profile.loginName, 'PainterOne');
    expect(profile.isAdmin, isTrue);
  });

  test('normalizes an empty login name to null', () {
    final profile = AppUserProfile.fromJson({
      'auth_user_id': 'auth-user-id',
      'login_name': '   ',
    });

    expect(profile.loginName, isNull);
  });
}
