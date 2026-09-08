import 'package:art_reference_app/services/connectivity_incident_store.dart';
import 'package:art_reference_app/services/user_activity_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final logger = UserActivityLogger.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => logger.sink = null);

  test('replays a backend failure after connectivity recovers', () async {
    final entries = <Map<String, Object?>>[];
    logger.sink = (entry) async => entries.add(entry);

    await ConnectivityIncidentStore.record(
      "SocketException: Failed host lookup: 'project.supabase.co'",
    );
    await ConnectivityIncidentStore.flush();

    expect(entries, hasLength(1));
    expect(entries.single['operation'], 'supabase_connectivity');
    expect(entries.single['status'], 'failed');
    expect(entries.single['error_message'], contains('Failed host lookup'));
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('pending_connectivity_incidents_v1'), isNull);
  });
}
