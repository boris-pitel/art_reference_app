import 'dart:convert';
import 'dart:io';

import 'r2_client.dart';

/// Shows whether the most recently added images have reached the backup.
///
/// The replication trigger is asynchronous and best effort, so "it should have
/// worked" is not the same as knowing. This answers the question directly for
/// the newest rows, which is what you want right after uploading something.
///
///   dart run tool/check_latest_backup.dart
///   dart run tool/check_latest_backup.dart --count 20
Future<void> main(List<String> arguments) async {
  final r2 = R2Client.fromEnvironment();
  final supabase = _supabase();

  if (r2 == null || supabase == null) {
    stderr.writeln('Missing credentials in .env.admin.');
    exitCode = 1;
    return;
  }

  final (url, key) = supabase;
  var count = 5;

  for (var i = 0; i < arguments.length - 1; i++) {
    if (arguments[i] == '--count') {
      count = int.tryParse(arguments[i + 1]) ?? 5;
    }
  }

  final client = HttpClient();

  try {
    final request = await client.getUrl(
      Uri.parse(
        '$url/rest/v1/image_assets'
        '?select=id,title,date_added,storage_path,thumbnail_storage_path'
        '&order=date_added.desc&limit=$count',
      ),
    );

    request.headers
      ..set('apikey', key)
      ..set('Authorization', 'Bearer $key');

    final response = await request.close();
    final rows = (jsonDecode(await response.transform(utf8.decoder).join())
            as List)
        .cast<Map<String, dynamic>>();

    stdout.writeln('The $count most recently added images:\n');

    var missing = 0;

    for (final row in rows) {
      final added = DateTime.tryParse('${row['date_added']}')?.toLocal();
      final age = added == null
          ? ''
          : _ago(DateTime.now().difference(added));

      stdout.writeln(
        '${row['title'] ?? '(untitled)'}  ·  added $age',
      );

      for (final field in const ['storage_path', 'thumbnail_storage_path']) {
        final path = row[field];
        if (path is! String || path.isEmpty) continue;

        final size = await r2.head('reference-images/$path');
        final label = field == 'storage_path' ? 'original ' : 'thumbnail';

        if (size == null) {
          missing++;
          stdout.writeln('  $label  NOT IN BACKUP');
        } else {
          stdout.writeln(
            '  $label  in backup, ${(size / 1024).toStringAsFixed(0)} KB',
          );
        }
      }

      stdout.writeln();
    }

    stdout.writeln(
      missing == 0
          ? 'All of them are in the backup.'
          : '$missing file(s) not yet replicated. '
              'Run: dart run tool/replicate_to_r2.dart',
    );

    if (missing > 0) exitCode = 1;
  } finally {
    client.close();
    r2.close();
  }
}

String _ago(Duration d) {
  if (d.inSeconds < 90) return '${d.inSeconds}s ago';
  if (d.inMinutes < 90) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} hours ago';
  return '${d.inDays} days ago';
}

(String, String)? _supabase() {
  String? url = Platform.environment['SUPABASE_URL']?.trim();
  String? key = Platform.environment['SUPABASE_SECRET_KEY']?.trim();

  final file = File('.env.admin');

  if (file.existsSync()) {
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;

      final name = trimmed.substring(0, separator).trim();
      final value = trimmed
          .substring(separator + 1)
          .trim()
          .replaceAll(RegExp(r'''^["']|["']$'''), '');

      if (name == 'SUPABASE_URL' && (url == null || url.isEmpty)) url = value;
      if (name == 'SUPABASE_SECRET_KEY' && (key == null || key.isEmpty)) {
        key = value;
      }
    }
  }

  if (url == null || key == null || url.isEmpty || key.isEmpty) return null;

  return (url.replaceFirst(RegExp(r'/$'), ''), key);
}
