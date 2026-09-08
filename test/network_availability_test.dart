import 'package:art_reference_app/services/network_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes the host lookup failure seen on Android', () {
    expect(
      NetworkAvailability.isNetworkFailure(
        "SocketException: Failed host lookup: 'project.supabase.co'",
      ),
      isTrue,
    );
  });

  test('recognizes a Supabase 5xx service failure', () {
    expect(
      NetworkAvailability.isNetworkFailure(
        'FunctionException(status: 503, details: unavailable)',
      ),
      isTrue,
    );
  });

  test('does not mistake authentication rejection for an outage', () {
    expect(
      NetworkAvailability.isNetworkFailure('Invalid login credentials'),
      isFalse,
    );
  });
}
