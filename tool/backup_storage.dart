import 'dart:convert';
import 'dart:io';

/// Copies every stored file out of Supabase to a local folder.
///
/// The database backups do not restore storage objects: after a loss the rows
/// describing every image would come back and the images themselves would not.
/// For a reference library that is the whole product, so this is the one piece
/// of data with no safety net.
///
/// Incremental — a file already present at the same size is skipped, so a
/// nightly run costs little after the first. Writes a manifest beside the files
/// recording what the server held at that moment, which is what makes a later
/// restore checkable rather than hopeful.
///
///   dart run tool/backup_storage.dart --out D:\painter-backup
///   dart run tool/backup_storage.dart --out D:\painter-backup --verify
Future<void> main(List<String> arguments) async {
  final credentials = _loadCredentials();

  if (credentials == null) {
    stderr.writeln('Missing SUPABASE_URL / SUPABASE_SECRET_KEY.');
    exitCode = 1;
    return;
  }

  final (url, key) = credentials;
  final destination = _valueFor(arguments, 'out') ?? 'storage-backup';
  final verifyOnly = arguments.contains('--verify');

  final root = Directory(destination);
  if (!verifyOnly) root.createSync(recursive: true);

  if (!root.existsSync()) {
    stderr.writeln('No backup at $destination to verify.');
    exitCode = 1;
    return;
  }

  final client = HttpClient();
  final started = DateTime.now();

  var downloaded = 0;
  var skipped = 0;
  var failed = 0;
  var missing = 0;
  var bytes = 0;

  final manifest = <Map<String, Object?>>[];

  try {
    final buckets = await _buckets(client, url, key);

    stdout.writeln(
      '${verifyOnly ? 'Verifying' : 'Backing up'} ${buckets.length} buckets '
      'to ${root.absolute.path}\n',
    );

    for (final bucket in buckets) {
      final objects = await _listAll(client, url, key, bucket);

      stdout.writeln('$bucket — ${objects.length} files');

      for (final object in objects) {
        final path = object['path'] as String;
        final size = (object['size'] as num?)?.toInt() ?? 0;
        final localFile = File(
          [root.path, bucket, ...path.split('/')].join(Platform.pathSeparator),
        );

        manifest.add({
          'bucket': bucket,
          'path': path,
          'size': size,
          'updated_at': object['updated_at'],
        });

        // Size is what the storage API reports without a second request per
        // file. It catches a truncated or absent copy, which is the failure
        // that actually happens; it would not catch a same-length corruption.
        final present = localFile.existsSync() && localFile.lengthSync() == size;

        if (verifyOnly) {
          if (!present) {
            missing++;
            stdout.writeln('  MISSING  $path');
          }
          continue;
        }

        if (present) {
          skipped++;
          continue;
        }

        try {
          final data = await _download(client, url, key, bucket, path);

          localFile.parent.createSync(recursive: true);
          localFile.writeAsBytesSync(data);

          downloaded++;
          bytes += data.length;

          if (downloaded % 25 == 0) {
            stdout.writeln('  $downloaded downloaded…');
          }
        } catch (error) {
          failed++;
          stderr.writeln('  FAILED   $path: $error');
        }
      }
    }

    if (!verifyOnly) {
      // Written last, so a manifest exists only for a run that got this far.
      File(
        [root.path, 'manifest.json'].join(Platform.pathSeparator),
      ).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'taken_at': started.toUtc().toIso8601String(),
          'file_count': manifest.length,
          'files': manifest,
        }),
      );
    }

    final elapsed = DateTime.now().difference(started);

    stdout.writeln('\n${'-' * 46}');

    if (verifyOnly) {
      stdout.writeln(
        missing == 0
            ? 'All ${manifest.length} files present at the expected size.'
            : '$missing of ${manifest.length} files MISSING or truncated.',
      );
      if (missing > 0) exitCode = 1;
    } else {
      stdout.writeln(
        'Downloaded $downloaded (${_mb(bytes)}), skipped $skipped already '
        'held, failed $failed, in ${elapsed.inSeconds}s.',
      );
      stdout.writeln('Manifest: ${manifest.length} files recorded.');
      if (failed > 0) exitCode = 1;
    }
  } finally {
    client.close();
  }
}

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

Future<List<String>> _buckets(
  HttpClient client,
  String url,
  String key,
) async {
  final response = await _json(client, 'GET', '$url/storage/v1/bucket', key);

  return [
    for (final bucket in response as List)
      if (bucket is Map && bucket['name'] is String) bucket['name'] as String,
  ];
}

/// Every object in a bucket, walking into folders.
///
/// The list endpoint returns one level at a time, and marks folders by giving
/// them a null id — so a flat call would silently return nothing but folder
/// names for any bucket that nests, which all of these do.
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
          'updated_at': item['updated_at'],
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

String? _valueFor(List<String> arguments, String name) {
  final flag = '--$name';

  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == flag && i + 1 < arguments.length) return arguments[i + 1];
    if (arguments[i].startsWith('$flag=')) {
      return arguments[i].substring(flag.length + 1);
    }
  }

  return null;
}

(String, String)? _loadCredentials() {
  String? read(String name) {
    final value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  var url = read('SUPABASE_URL');
  var key = read('SUPABASE_SECRET_KEY') ?? read('SUPABASE_SERVICE_ROLE_KEY');

  if (url == null || key == null) {
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

        if (name == 'SUPABASE_URL') url ??= value;
        if (name == 'SUPABASE_SECRET_KEY' ||
            name == 'SUPABASE_SERVICE_ROLE_KEY') {
          key ??= value;
        }
      }
    }
  }

  if (url == null || key == null) return null;

  return (url.replaceFirst(RegExp(r'/$'), ''), key);
}
