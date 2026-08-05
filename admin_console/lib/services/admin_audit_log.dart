import 'dart:convert';
import 'dart:io';

class AdminAuditLog {
  AdminAuditLog({required this.repositoryRoot});

  final Directory repositoryRoot;

  File get file => File(
    '${repositoryRoot.path}${Platform.pathSeparator}.admin-audit'
    '${Platform.pathSeparator}painter-admin.jsonl',
  );

  Future<void> write({
    required String action,
    required String targetEmail,
    required String result,
    String? authUserId,
    Map<String, Object?> details = const {},
  }) async {
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

  Future<List<Map<String, dynamic>>> readAll() async {
    if (!await file.exists()) return [];
    final records = <Map<String, dynamic>>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final value = jsonDecode(line);
        if (value is Map) {
          records.add(Map<String, dynamic>.from(value));
        }
      } on FormatException {
        records.add({
          'timestamp': '',
          'actor': '',
          'action': 'Invalid audit record',
          'target_email': '',
          'result': 'error',
        });
      }
    }
    return records.reversed.toList();
  }
}
