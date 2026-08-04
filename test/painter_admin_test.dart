import 'package:flutter_test/flutter_test.dart';

import '../tool/painter_admin/src/admin_service.dart';

void main() {
  final service = AdminService(
    url: 'https://example.supabase.co',
    secretKey: 'test-secret-not-used-for-network-calls',
  );

  test('normalizes email identity consistently', () {
    expect(
      service.normalizeEmail('  KathyPitel29@GMAIL.COM '),
      'kathypitel29@gmail.com',
    );
    expect(
      service.dataUserIdForEmail('KathyPitel29@gmail.com'),
      service.dataUserIdForEmail(' kathypitel29@GMAIL.COM '),
    );
  });

  test('different emails receive different data owner IDs', () {
    expect(
      service.dataUserIdForEmail('first@example.com'),
      isNot(service.dataUserIdForEmail('second@example.com')),
    );
  });
}
