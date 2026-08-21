import 'dart:convert';
import 'dart:io';

/// Browses the activity log in a browser, with selectable columns, built-up
/// filters, and — the reason this exists — unfinished operations marked.
///
/// An operation that started and never reported an end is what a silent
/// failure looks like: the photo library accepted the file and said nothing,
/// the request never came back. Nothing else in the log says so, because the
/// evidence is a row that is *absent*. Pairing each start with its end makes
/// that absence visible.
///
/// Runs as a local process rather than a screen in the app because the log is
/// readable only with the service key, which must not ship inside the app.
/// The key stays here; the page only ever sees rows.
///
///   dart run tool/log_explorer.dart
///   dart run tool/log_explorer.dart --port 8788 --no-open
Future<void> main(List<String> arguments) async {
  final credentials = _loadCredentials();

  if (credentials == null) {
    stderr.writeln(
      'Administrative credentials are missing. Put SUPABASE_URL and '
      'SUPABASE_SECRET_KEY in .env.admin at the project root, or set them in '
      'the environment.',
    );
    exitCode = 1;
    return;
  }

  final port =
      int.tryParse(_valueFor(arguments, 'port') ?? '') ?? 8787;

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

  final address = 'http://localhost:$port';
  stdout.writeln('Activity log explorer running at $address');
  stdout.writeln('Press Ctrl+C to stop.');

  if (!arguments.contains('--no-open')) {
    await _openInBrowser(address);
  }

  await for (final request in server) {
    try {
      switch (request.uri.path) {
        case '/':
          // Read per request, so editing the page is a browser refresh rather
          // than a restart.
          request.response
            ..headers.contentType = ContentType.html
            ..write(File('tool/log_explorer_page.html').readAsStringSync());
        case '/api/query':
          final rows = await _fetchRows(credentials, request.uri
              .queryParameters);
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(rows));
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
    } catch (error) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'error': '$error'}));
    }

    await request.response.close();
  }
}

/// Runs the query and pairs each start with its end.
///
/// The pairing is done here rather than in SQL because it is a scan over the
/// rows already fetched — and because expressing "a row whose partner does not
/// exist" as a filter would mean a self-join the page cannot compose.
Future<List<Map<String, dynamic>>> _fetchRows(
  _Credentials credentials,
  Map<String, String> parameters,
) async {
  final filters = <String, String>{};

  // Each filter arrives as three separate parameters rather than one
  // delimited value. A value can itself contain spaces — searching an
  // error message for "not found" — so any separator packed into a
  // single parameter breaks on the first such search.
  for (var index = 0; parameters.containsKey('f${index}c'); index++) {
    final column = parameters['f${index}c']!;
    final operator = parameters['f${index}o'] ?? 'eq';
    final value = parameters['f${index}v'] ?? '';

    if (!_columns.contains(column)) continue;

    final encoded = switch (operator) {
      'eq' => 'eq.$value',
      'neq' => 'neq.$value',
      'contains' => 'ilike.*$value*',
      'gt' => 'gt.$value',
      'lt' => 'lt.$value',
      'empty' => 'is.null',
      'present' => 'not.is.null',
      _ => null,
    };

    if (encoded != null) filters[column] = encoded;
  }

  final limit = int.tryParse(parameters['limit'] ?? '') ?? 500;

  final query = <String, String>{
    'select': {..._columns, 'session_id'}.join(','),
    'order': 'created_at.desc',
    'limit': '$limit',
    ...filters,
  };

  final url = Uri.parse('${credentials.url}/rest/v1/user_activity_logs')
      .replace(queryParameters: query);

  final client = HttpClient();

  try {
    final request = await client.getUrl(url);
    request.headers
      ..set('apikey', credentials.key)
      ..set('Authorization', 'Bearer ${credentials.key}');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Query failed (${response.statusCode}): $body');
    }

    final rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();

    return _markUnfinished(rows);
  } finally {
    client.close();
  }
}

/// Flags every `started` row that has no matching end, and carries the elapsed
/// time back onto the start so a row shows its own duration.
///
/// A start and its end share a session, an operation and a target; the end is
/// whichever qualifying row came after it. Rows are newest-first from the
/// server, so this walks them oldest-first to pair in the order they happened.
List<Map<String, dynamic>> _markUnfinished(List<Map<String, dynamic>> rows) {
  const endStatuses = {'succeeded', 'failed', 'cancelled'};

  // Which operations record an end at all. Several log only a start — they are
  // not stranded work, they are gaps in instrumentation, and flagging them
  // would bury the failures this exists to surface under a wall of red. An
  // operation earns the check by having ended at least once.
  final instrumented = <String>{
    for (final row in rows)
      if (endStatuses.contains(row['status'])) '${row['operation']}',
  };

  final ordered = rows.reversed.toList();

  // Keyed by session and operation only, holding every start still waiting for
  // its end. The target cannot be part of the key: an edit's end names the
  // asset it produced, not the one it began with, so requiring the two to
  // match reported every completed edit as stranded.
  final open = <String, List<Map<String, dynamic>>>{};

  String keyFor(Map<String, dynamic> row) =>
      '${row['session_id']}|${row['operation']}';

  for (final row in ordered) {
    final key = keyFor(row);
    final status = row['status'];

    if (status == 'started') {
      if (!instrumented.contains('${row['operation']}')) {
        // Recorded so the page can say so, rather than staying silent about an
        // operation whose outcome is never captured anywhere.
        row['no_end_recorded'] = true;
        continue;
      }

      open.putIfAbsent(key, () => []).add(row);
      row['unfinished'] = true;
    } else if (endStatuses.contains(status)) {
      final waiting = open[key];
      Map<String, dynamic>? start;

      if (waiting != null && waiting.isNotEmpty) {
        // Prefer a start naming the same target — right when several of the
        // same operation overlap. Otherwise the oldest still-open start, since
        // these are sequential user actions and the first to begin is the
        // first to end.
        final exact = waiting.indexWhere(
          (candidate) => candidate['target_id'] == row['target_id'],
        );

        start = waiting.removeAt(exact < 0 ? 0 : exact);
      }

      if (start != null) {
        start['unfinished'] = false;
        start['duration_ms'] ??= row['duration_ms'];

        // Wall-clock between the two rows, which includes any time the user
        // spent in a system dialog — worth seeing next to the measured
        // duration, since a long gap there is a person, not slow code.
        final startedAt = DateTime.tryParse('${start['created_at']}');
        final endedAt = DateTime.tryParse('${row['created_at']}');

        if (startedAt != null && endedAt != null) {
          start['elapsed_ms'] = endedAt.difference(startedAt).inMilliseconds;
        }
      }
    }
  }

  return rows;
}

const _columns = <String>[
  'created_at',
  'user_email',
  'operation',
  'status',
  'duration_ms',
  'platform',
  'app_version',
  'target_type',
  'target_id',
  'parent_image_id',
  'error_message',
  'details',
];

class _Credentials {
  const _Credentials(this.url, this.key);

  final String url;
  final String key;
}

_Credentials? _loadCredentials() {
  String? read(String name) {
    final value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  var url = read('SUPABASE_URL');
  var key = read('SUPABASE_SECRET_KEY') ?? read('SUPABASE_SERVICE_ROLE_KEY');

  if (url == null || key == null) {
    final file = File('.env.admin');

    if (file.existsSync()) {
      final values = <String, String>{};

      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        final separator = trimmed.indexOf('=');
        if (separator <= 0) continue;

        values[trimmed.substring(0, separator).trim()] = trimmed
            .substring(separator + 1)
            .trim()
            .replaceAll(RegExp(r'''^["']|["']$'''), '');
      }

      url ??= values['SUPABASE_URL'];
      key ??= values['SUPABASE_SECRET_KEY'] ??
          values['SUPABASE_SERVICE_ROLE_KEY'];
    }
  }

  if (url == null || key == null) return null;

  return _Credentials(url.replaceFirst(RegExp(r'/$'), ''), key);
}

String? _valueFor(List<String> arguments, String name) {
  final flag = '--$name';

  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i] == flag && i + 1 < arguments.length) {
      return arguments[i + 1];
    }
    if (arguments[i].startsWith('$flag=')) {
      return arguments[i].substring(flag.length + 1);
    }
  }

  return null;
}

Future<void> _openInBrowser(String address) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', address]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [address]);
    } else {
      await Process.run('xdg-open', [address]);
    }
  } catch (_) {
    // Opening a browser is a convenience; the address is printed either way.
  }
}
