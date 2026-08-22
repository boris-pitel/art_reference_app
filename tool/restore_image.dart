import 'dart:convert';
import 'dart:io';

import 'r2_client.dart';

/// Puts a deleted image back: the file from the backup, the rows from the
/// archive.
///
/// Neither half is enough alone. R2 holds the bytes but knows nothing about
/// titles, categories or keywords; the archive holds the rows but no pixels.
/// A restore that did only one of them would look like it worked and leave
/// either an invisible file or a broken thumbnail.
///
/// Nothing is written without --confirm. Restoring is not destructive, but it
/// is the kind of operation people run while alarmed, and printing the plan
/// first is cheap.
///
///   dart run tool/restore_image.dart --list
///   dart run tool/restore_image.dart --list --email someone@example.com
///   dart run tool/restore_image.dart --image `<uuid>`
///   dart run tool/restore_image.dart --image `<uuid>` --confirm
Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);

  if (options.showHelp) {
    stdout.writeln(_usage);
    return;
  }

  final r2 = R2Client.fromEnvironment();
  final supabase = _supabaseCredentials();

  if (r2 == null || supabase == null) {
    stderr.writeln(
      'Missing credentials. Expected R2_* and SUPABASE_* in .env.admin.',
    );
    exitCode = 1;
    return;
  }

  final api = _SupabaseAdmin(supabase.$1, supabase.$2);

  try {
    if (options.imageId == null) {
      await _list(api, r2, options);
    } else {
      await _restore(api, r2, options);
    }
  } on _RestoreFailure catch (failure) {
    stderr.writeln('\n${failure.message}');
    exitCode = 1;
  } finally {
    api.close();
    r2.close();
  }
}

// --- listing ---------------------------------------------------------------

Future<void> _list(_SupabaseAdmin api, R2Client r2, _Options options) async {
  final filters = <String>[
    'table_name=eq.image_assets',
    'select=deleted_at,image_id,user_id,row_data',
    'order=deleted_at.desc',
    'limit=${options.limit}',
  ];

  if (options.days != null) {
    final since = DateTime.now().toUtc().subtract(Duration(days: options.days!));
    filters.add('deleted_at=gte.${since.toIso8601String()}');
  }

  if (options.email != null) {
    filters.add('row_data->>user_email=eq.${Uri.encodeComponent(options.email!)}');
  }

  final rows = await api.select('deleted_row_archive', filters);

  if (rows.isEmpty) {
    stdout.writeln(
      'Nothing in the archive matches.\n\n'
      'Only deletions made after the archive existed are recoverable; anything '
      'removed before that left its bytes in the backup but no rows.',
    );
    return;
  }

  // One listing of the deleted prefix serves every row, rather than a HEAD per
  // file.
  final retired = await _retiredObjects(r2);

  stdout.writeln('Deleted images that can be restored:\n');

  for (final row in rows) {
    final data = (row['row_data'] as Map).cast<String, dynamic>();
    final when = DateTime.tryParse('${row['deleted_at']}')?.toLocal();
    final original = data['storage_path'];
    final held = original is String &&
        retired.containsKey('reference-images/$original');

    stdout.writeln('${data['title'] ?? '(untitled)'}');
    stdout.writeln('  image     ${row['image_id']}');
    stdout.writeln('  owner     ${data['user_email'] ?? row['user_id']}');
    stdout.writeln(
      '  deleted   ${when == null ? 'unknown' : _ago(DateTime.now().difference(when))}',
    );
    stdout.writeln(
      '  file      ${held ? 'in the backup' : 'NOT in the backup — rows only'}',
    );
    stdout.writeln();
  }

  stdout.writeln(
    'To restore one:\n'
    '  dart run tool/restore_image.dart --image <id>',
  );
}

// --- restoring -------------------------------------------------------------

Future<void> _restore(_SupabaseAdmin api, R2Client r2, _Options options) async {
  final imageId = options.imageId!;

  final archived = await api.select('deleted_row_archive', [
    'table_name=eq.image_assets',
    'image_id=eq.$imageId',
    'select=deleted_at,image_id,user_id,row_data',
    'order=deleted_at.desc',
    'limit=1',
  ]);

  if (archived.isEmpty) {
    throw _RestoreFailure(
      'Nothing archived for $imageId.\n'
      'Either the id is wrong, or it was deleted before the archive existed.',
    );
  }

  final event = archived.first;
  final deletedAt = '${event['deleted_at']}';

  final live = await api.select('image_assets', [
    'id=eq.$imageId',
    'select=id',
  ]);

  if (live.isNotEmpty) {
    throw _RestoreFailure(
      'That image already exists. Nothing to restore.',
    );
  }

  // Everything removed by the same delete, so a sketch derived from the image
  // comes back with it rather than being silently dropped.
  final family = await api.select('deleted_row_archive', [
    'deleted_at=eq.${Uri.encodeComponent(deletedAt)}',
    'table_name=eq.image_assets',
    'select=image_id,row_data',
  ]);

  final relationships = await api.select('deleted_row_archive', [
    'deleted_at=eq.${Uri.encodeComponent(deletedAt)}',
    'table_name=eq.image_relationships',
    'select=image_id,related_image_id',
  ]);

  final wanted = <String>{imageId};

  for (final link in relationships) {
    final parent = '${link['image_id']}';
    final child = '${link['related_image_id']}';
    if (parent == imageId) wanted.add(child);
    if (child == imageId) wanted.add(parent);
  }

  final images = family
      .where((row) => wanted.contains('${row['image_id']}'))
      .toList();

  final retired = await _retiredObjects(r2);
  final plan = <_FileToRestore>[];
  var missing = 0;

  for (final row in images) {
    final data = (row['row_data'] as Map).cast<String, dynamic>();

    for (final field in const ['storage_path', 'thumbnail_storage_path']) {
      final path = data[field];
      if (path is! String || path.isEmpty) continue;

      final key = retired['reference-images/$path'];

      if (key == null) {
        missing++;
        stdout.writeln('  MISSING from the backup: $path');
      } else {
        plan.add(_FileToRestore(path: path, backupKey: key));
      }
    }
  }

  final title = (images.firstWhere(
    (row) => '${row['image_id']}' == imageId,
    orElse: () => images.first,
  )['row_data'] as Map)['title'];

  stdout.writeln('Restoring "${title ?? '(untitled)'}"\n');
  stdout.writeln('  deleted        ${DateTime.tryParse(deletedAt)?.toLocal()}');
  stdout.writeln('  images         ${images.length}'
      '${images.length > 1 ? ' (including derived sketches)' : ''}');
  stdout.writeln('  files to copy  ${plan.length}');

  if (missing > 0) {
    stdout.writeln(
      '\n$missing file(s) are not in the backup. Their rows would come back '
      'pointing at nothing, which shows as a broken image in the app.',
    );

    if (!options.force) {
      throw _RestoreFailure(
        'Refusing to restore a partial image. Pass --force to do it anyway.',
      );
    }
  }

  if (!options.confirm) {
    stdout.writeln(
      '\nThis was a dry run. Nothing was written.\n'
      'Run it again with --confirm to restore.',
    );
    return;
  }

  // Files first. Inserting the rows fires replication, which reads the object
  // out of storage to copy it back to the live backup path — with no file
  // there, the restored image would come back unprotected.
  stdout.writeln('\nCopying files back into storage...');

  for (final file in plan) {
    final bytes = await r2.get(file.backupKey);

    if (bytes == null) {
      throw _RestoreFailure(
        'The backup object vanished between listing and reading: '
        '${file.backupKey}',
      );
    }

    await api.upload(
      bucket: 'reference-images',
      path: file.path,
      bytes: bytes,
      contentType: _sniffContentType(bytes),
    );

    stdout.writeln('  ${file.path}  (${_size(bytes.length)})');
  }

  stdout.writeln('\nRestoring rows...');

  final result = await api.rpc('restore_archived_image', {
    'p_image_id': imageId,
  });

  if (result['restored'] != true) {
    throw _RestoreFailure('The database refused: ${result['reason']}');
  }

  stdout.writeln('  ${result['restored_images']} image row(s), '
      '${result['restored_child_rows']} related row(s)');

  // Say whether it is really back, rather than assuming the writes above add
  // up to a working image.
  stdout.writeln('\nChecking...');

  final restored = await api.select('image_assets', [
    'id=eq.$imageId',
    'select=id,title,storage_path,thumbnail_storage_path',
  ]);

  if (restored.isEmpty) {
    throw _RestoreFailure('The row is still not there. Nothing was restored.');
  }

  for (final file in plan) {
    final exists = await api.storageExists('reference-images', file.path);
    stdout.writeln(
      '  ${exists ? 'in storage' : 'MISSING FROM STORAGE'}  ${file.path}',
    );
  }

  stdout.writeln(
    '\nRestored. Replication runs on the insert, so the file should be back in '
    'the live backup within a few seconds:\n'
    '  dart run tool/replicate_to_r2.dart --check',
  );
}

/// Keys under deleted/, indexed by the path they had before deletion.
///
/// The prefix carries the date of removal, which is not known in advance, so
/// the whole prefix is listed once and matched by suffix. The most recent
/// retirement wins if a path was deleted more than once.
Future<Map<String, String>> _retiredObjects(R2Client r2) async {
  final keys = await r2.list('deleted/');
  final byOriginal = <String, String>{};

  final dated = keys.keys.toList()..sort();

  for (final key in dated) {
    final parts = key.split('/');
    if (parts.length < 3) continue;

    byOriginal[parts.sublist(2).join('/')] = key;
  }

  return byOriginal;
}

/// Content type from the bytes themselves. The backup stores the object, not
/// the metadata the original upload carried, and guessing from the path is not
/// possible: originals are stored without an extension.
String _sniffContentType(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }

  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }

  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }

  if (bytes.length >= 6 &&
      String.fromCharCodes(bytes.sublist(0, 6)).startsWith('GIF8')) {
    return 'image/gif';
  }

  return 'application/octet-stream';
}

// --- plumbing --------------------------------------------------------------

class _FileToRestore {
  const _FileToRestore({required this.path, required this.backupKey});

  final String path;
  final String backupKey;
}

class _RestoreFailure implements Exception {
  const _RestoreFailure(this.message);

  final String message;
}

class _SupabaseAdmin {
  _SupabaseAdmin(this.url, this.key);

  final String url;
  final String key;
  final HttpClient _client = HttpClient();

  void close() => _client.close();

  void _authorise(HttpClientRequest request) {
    request.headers
      ..set('apikey', key)
      ..set('Authorization', 'Bearer $key');
  }

  Future<List<Map<String, dynamic>>> select(
    String table,
    List<String> filters,
  ) async {
    final request = await _client.getUrl(
      Uri.parse('$url/rest/v1/$table?${filters.join('&')}'),
    );

    _authorise(request);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 300) {
      throw _RestoreFailure('Query on $table failed: '
          '${response.statusCode} $body');
    }

    return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> rpc(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final request = await _client.postUrl(
      Uri.parse('$url/rest/v1/rpc/$name'),
    );

    _authorise(request);
    request.headers.contentType = ContentType.json;

    final payload = utf8.encode(jsonEncode(arguments));
    request.contentLength = payload.length;
    request.add(payload);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 300) {
      throw _RestoreFailure('$name failed: ${response.statusCode} $body');
    }

    return (jsonDecode(body) as Map).cast<String, dynamic>();
  }

  Future<void> upload({
    required String bucket,
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    final request = await _client.postUrl(
      Uri.parse('$url/storage/v1/object/$bucket/$path'),
    );

    _authorise(request);
    request.headers
      ..set('Content-Type', contentType)
      // The object is meant to be gone; if a fragment of it survived a partial
      // earlier attempt, overwrite rather than fail.
      ..set('x-upsert', 'true');

    request.contentLength = bytes.length;
    request.add(bytes);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode >= 300) {
      throw _RestoreFailure(
        'Upload of $path failed: ${response.statusCode} $body',
      );
    }
  }

  Future<bool> storageExists(String bucket, String path) async {
    final request = await _client.openUrl(
      'HEAD',
      Uri.parse('$url/storage/v1/object/$bucket/$path'),
    );

    _authorise(request);

    final response = await request.close();
    await response.drain<void>();

    return response.statusCode == 200;
  }
}

class _Options {
  const _Options({
    this.imageId,
    this.email,
    this.days,
    this.limit = 25,
    this.confirm = false,
    this.force = false,
    this.showHelp = false,
  });

  final String? imageId;
  final String? email;
  final int? days;
  final int limit;
  final bool confirm;
  final bool force;
  final bool showHelp;

  static _Options parse(List<String> arguments) {
    String? imageId;
    String? email;
    int? days;
    var limit = 25;
    var confirm = false;
    var force = false;
    var help = arguments.isEmpty;

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      String? next() => i + 1 < arguments.length ? arguments[++i] : null;

      switch (argument) {
        case '--image':
          imageId = next();
        case '--email':
          email = next();
        case '--days':
          days = int.tryParse(next() ?? '');
        case '--limit':
          limit = int.tryParse(next() ?? '') ?? 25;
        case '--confirm':
          confirm = true;
        case '--force':
          force = true;
        case '--list':
          break;
        case '--help' || '-h':
          help = true;
      }
    }

    return _Options(
      imageId: imageId,
      email: email,
      days: days,
      limit: limit,
      confirm: confirm,
      force: force,
      showHelp: help,
    );
  }
}

const _usage = '''
Puts a deleted image back, file and rows together.

  --list                  what can be restored (default when no --image)
  --image <uuid>          restore this image; prints the plan and stops
  --confirm               actually do it
  --force                 restore even when some files are missing
  --email <address>       narrow the listing to one owner
  --days <n>              narrow the listing to recent deletions
  --limit <n>             how many to list (default 25)

  dart run tool/restore_image.dart --list --days 30
  dart run tool/restore_image.dart --image 1234abcd-... --confirm
''';

String _size(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(0)} KB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

String _ago(Duration d) {
  if (d.inMinutes < 90) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} hours ago';
  return '${d.inDays} days ago';
}

(String, String)? _supabaseCredentials() {
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
