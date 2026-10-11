import 'package:art_reference_app/services/resume_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('retains previous run evidence and bounds the stored log', () async {
    SharedPreferences.setMockInitialValues({
      ResumeDiagnostics.storageKey: ['previous-run lifecycle paused'],
    });
    final log = ResumeDiagnostics();
    await log.initialize();
    expect(log.export(), contains('previous-run lifecycle paused'));
    expect(log.export(), contains('run=${log.runId} launch'));
    for (var i = 0; i < 310; i++) {
      log.record('event $i');
    }
    expect(log.export().split('\n'), hasLength(300));
    expect(log.export(), contains('event 309'));
    expect(log.export(), isNot(contains('previous-run')));
  });
}
