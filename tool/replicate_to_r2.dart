import 'dart:convert';
import 'dart:io';

import 'r2_client.dart';

/// Replicates Supabase Storage to the Cloudflare R2 backup bucket.
///
/// Supabase's database backups restore rows, not stored objects: after a loss
/// every row describing an image would come back and no image would. For a
/// reference library that is the whole product, and it is the only data with
/// no safety net.
///
/// Serves two purposes. Run once, it backfills everything. Run on a schedule,
/// it reconciles — the webhook replication is best effort, so this is what
/// turns "usually replicated" into "verifiably replicated" and reports the gap
/// it found rather than quietly closing it.
///
///   dart run tool/replicate_to_r2.dart
///   dart run tool/replicate_to_r2.dart --check
Future<void> main(List<String> arguments) async {
  final supabase = _supabaseCredentials();
  final r2 = R2Client.fromEnvironment();

  if (supabase == null || r2 == null) {
    stderr.writeln(
      'Missing credentials. .env.admin needs SUPABASE_URL, '
      'SUPABASE_SECRET_KEY, and the four R2_ values.',
    );
    exitCode = 1;
    return;
  }

  final (url, key) = supabase;
  final checkOnly = arguments.contains('--check');
  final client = HttpClient();
  final started = DateTime.now();

  var copied = 0;
  var present = 0;
  var failed = 0;
  var bytes = 0;
  final missing = <String>[];

  try {
    stdout.writeln(
      '${checkOnly ? 'Checking' : 'Replicating'} Supabase Storage against '
      'r2://${r2.bucket}\n',
    );

    // One listing of the destination up front, rather than a HEAD per file.
    // At several hundred files that is the difference between a few seconds
    // and several minutes.
    final held = await r2.list();
    stdout.writeln('Backup currently holds ${held.length} objects.\n');

    for (final bucket in await _buckets(client, url, key)) {
      final objects = await _listAll(client, url, key, bucket);
      stdout.writeln('$bucket — ${objects.length} files');

      for (final object in objects) {
        final path = object['path'] as String;
        final size = (object['size'] as num?)?.toInt() ?? 0;
        final destination = '$bucket/$path';

        // Size is enough here because images are immutable once uploaded: an
        // edit creates a new asset rather than overwriting one. It would not
        // be enough if files were rewritten in place.
        if (held[destination] == size) {
          present++;
          continue;
        }

        if (checkOnly) {
          missing.add(destination);
          continue;
        }

        try {
          final data = await _download(client, url, key, bucket, path);
          await r2.put(destination, data, contentType: _contentType(path));

          copied++;
          bytes += data.length;

          if (copied % 25 == 0) stdout.writeln('  $copied copied…');
        } catch (error) {
          failed++;
          stderr.writeln('  FAILED $destination: $error');
        }
      }
    }

    final elapsed = DateTime.now().difference(started);

    stdout.writeln('\n${'-' * 52}');

    if (checkOnly) {
      stdout.writeln(
        missing.isEmpty
            ? 'Every stored file is present in the backup.'
            : '${missing.length} file(s) NOT in the backup:',
      );

      for (final path in missing.take(20)) {
        stdout.writeln('  $path');
      }
      if (missing.length > 20) {
        stdout.writeln('  …and ${missing.length - 20} more');
      }

      if (missing.isNotEmpty) exitCode = 1;
    } else {
      stdout.writeln(
        'Copied $copied (${(bytes / 1024 / 1024).toStringAsFixed(1)} MB), '
        '$present already held, $failed failed, in ${elapsed.inSeconds}s.',
      );

      if (failed > 0) exitCode = 1;
    }
  } finally {
    client.close();
    r2.close();
  }
}

String _contentType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  return 'image/jpeg';
}

Future<List<String>> _buckets(HttpClient client, String url, String key) async {
  final response = await _json(client, 'GET', '$url/storage/v1/bucket', key);

  return [
    for (final bucket in response as List)
      if (bucket is Map && bucket['name'] is String) bucket['name'] as String,
  ];
}

/// Walks into folders: the list endpoint returns one level at a time and marks
/// folders with a null id, so a flat call returns folder names and no files.
Future<List<Map<String, Object?>>> _listAll(
  HttpClient client,
  String url,
  String key,
  String bucket, [
  String prefix = '',
]) async {
  final found = <Map<String, Object?>>[];
  var offset = 0;

  while (true) {
    final page = await _json(
      client,
      'POST',
      '$url/storage/v1/object/list/$bucket',
      key,
      body: {'prefix': prefix, 'limit': 100, 'offset': offset},
    );

    final items = page as List;
    if (items.isEmpty) break;

    for (final item in items) {
      if (item is! Map) continue;

      final name = item['name'] as String?;
      if (name == null || name.isEmpty) continue;

      final path = prefix.isEmpty ? name : '$prefix/$name';

      if (item['id'] == null) {
        found.addAll(await _listAll(client, url, key, bucket, path));
      } else {
        found.add({
          'path': path,
          'size': (item['metadata'] as Map?)?['size'],
        });
      }
    }

    if (items.length < 100) break;
    offset += 100;
  }

  return found;
}

Future<List<int>> _download(
  HttpClient client,
  String url,
  String key,
  String bucket,
  String path,
) async {
  final encoded = path.split('/').map(Uri.encodeComponent).join('/');
  final request = await client.getUrl(
    Uri.parse('$url/storage/v1/object/$bucket/$encoded'),
  );

  request.headers
    ..set('apikey', key)
    ..set('Authorization', 'Bearer $key');

  final response = await request.close();

  if (response.statusCode < 200 || response.statusCode >= 300) {
    await response.drain<void>();
    throw StateError('HTTP ${response.statusCode}');
  }

  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
  }

  return bytes;
}

Future<Object?> _json(
  HttpClient client,
  String method,
  String url,
  String key, {
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(method, Uri.parse(url));

  request.headers
    ..set('apikey', key)
    ..set('Authorization', 'Bearer $key')
    ..set('Content-Type', 'application/json');

  if (body != null) request.write(jsonEncode(body));

  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('$method $url -> ${response.statusCode}: $text');
  }

  return text.isEmpty ? null : jsonDecode(text);
}

(String, String)? _supabaseCredentials() {
  String? url = Platform.environment['SUPABASE_URL']?.trim();
  String? key = (Platform.environment['SUPABASE_SECRET_KEY'] ??
          Platform.environment['SUPABASE_SERVICE_ROLE_KEY'])
      ?.trim();

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
      if ((name == 'SUPABASE_SECRET_KEY' ||
              name == 'SUPABASE_SERVICE_ROLE_KEY') &&
          (key == null || key.isEmpty)) {
        key = value;
      }
    }
  }

  if (url == null || key == null || url.isEmpty || key.isEmpty) return null;

  return (url.replaceFirst(RegExp(r'/$'), ''), key);
}
