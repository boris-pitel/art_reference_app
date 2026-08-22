// Verifies that files in the R2 backup can actually be restored.
//
// Matching sizes are not proof — a failed download writes an error page of
// plausible length, and it sits in the backup looking like a file until the
// day it is needed. This compares hashes against what Supabase still holds.
//
//   dart run tool/verify_r2_backup.dart

import 'dart:io';

import 'package:crypto/crypto.dart';

import 'r2_client.dart';

/// Pulls a few objects back out of R2 and compares them byte for byte with
/// what Supabase still holds.
///
/// Matching sizes are not proof: a failed download writes an error page of
/// plausible length, and that sits in a backup looking like a file until the
/// day it is needed. Comparing hashes is the only check that answers "could
/// this actually be restored".
Future<void> main() async {
  final r2 = R2Client.fromEnvironment();
  if (r2 == null) {
    stderr.writeln('R2 not configured');
    exit(1);
  }

  final env = <String, String>{};
  for (final line in File('.env.admin').readAsLinesSync()) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final i = t.indexOf('=');
    if (i > 0) {
      env[t.substring(0, i).trim()] =
          t.substring(i + 1).trim().replaceAll(RegExp(r'''^["']|["']$'''), '');
    }
  }

  final url = env['SUPABASE_URL']!;
  final key = env['SUPABASE_SECRET_KEY']!;
  final client = HttpClient();

  // Spread the sample across buckets and sizes rather than taking the first
  // few, which would all come from one folder.
  final held = await r2.list();
  final entries = held.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final sample = <MapEntry<String, int>>[
    entries.first,
    entries[entries.length ~/ 2],
    entries.last,
    ...entries.where((e) => e.key.startsWith('message-images/')).take(1),
  ];

  var failures = 0;

  for (final entry in sample) {
    final slash = entry.key.indexOf('/');
    final bucket = entry.key.substring(0, slash);
    final path = entry.key.substring(slash + 1);

    final backupBytes = await r2.get(entry.key);

    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    final request = await client.getUrl(
      Uri.parse('$url/storage/v1/object/$bucket/$encoded'),
    );
    request.headers
      ..set('apikey', key)
      ..set('Authorization', 'Bearer $key');
    final response = await request.close();

    final sourceBytes = <int>[];
    await for (final chunk in response) {
      sourceBytes.addAll(chunk);
    }

    final sourceHash = sha256.convert(sourceBytes).toString();
    final backupHash = sha256.convert(backupBytes ?? const []).toString();
    final identical = sourceHash == backupHash;

    final magic = (backupBytes ?? const [])
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    stdout.writeln(
      '  ${identical ? 'PASS' : 'FAIL'}  ${entry.key.length > 52 ? '…${entry.key.substring(entry.key.length - 50)}' : entry.key}',
    );
    stdout.writeln(
      '        ${(entry.value / 1024).toStringAsFixed(0)} KB, magic $magic, '
      'hash ${identical ? 'matches source' : 'DIFFERS'}',
    );

    if (!identical) failures++;
  }

  client.close();
  r2.close();

  stdout.writeln(
    failures == 0
        ? '\nRestored copies are byte-identical to the originals.'
        : '\n$failures sampled file(s) do NOT match the source.',
  );

  exit(failures == 0 ? 0 : 1);
}
