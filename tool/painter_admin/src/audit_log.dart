import 'dart:convert';
import 'dart:io';

class AuditLog {
  AuditLog({this.path = '.admin-audit/painter-admin.jsonl'});

  final String path;

  Future<void> write({
    required String action,
    required String targetEmail,
    required String result,
    String? authUserId,
    Map<String, Object?> details = const {},
  }) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final actor =
        Platform.environment['USERNAME'] ??
        Platform.environment['USER'] ??
        'unknown';
    final record = <String, Object?>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'actor': actor,
      'action': action,
      'target_email': targetEmail,
      'auth_user_id': ?authUserId,
      'result': result,
      ...details,
    };
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}
