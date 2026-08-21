import 'dart:convert';
import 'dart:io';

/// Exports rows from user_activity_logs to a CSV file.
///
/// Every filter is optional and they combine: given none, it exports the most
/// recent activity across all users. Reads credentials from the environment in
/// the same way as the administration console, so it never holds a key itself.
///
///   dart run tool/export_activity_log.dart
///   dart run tool/export_activity_log.dart --email someone@example.com
///   dart run tool/export_activity_log.dart --operation image_upload --status failed
///   dart run tool/export_activity_log.dart --since 2026-08-01 --limit 5000
///
/// Options:
///   --email      only this user
///   --operation  only this operation, e.g. login, image_upload, image_full_view
///   --status     started | succeeded | failed | cancelled
///   --since      ISO date or timestamp, inclusive
///   --until      ISO date or timestamp, exclusive
///   --limit      maximum rows (default 1000, server caps very large pages)
///   --out        output path (default activity-log-TIMESTAMP.csv)
///   --json       write JSON instead of CSV
Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);

  if (options.showHelp) {
    stdout.writeln(_usage);
    return;
  }

  final url = Platform.environment['SUPABASE_URL']?.trim() ?? '';
  final key =
      (Platform.environment['SUPABASE_SECRET_KEY'] ??
              Platform.environment['SUPABASE_SERVICE_ROLE_KEY'])
          ?.trim() ??
      '';

  if (url.isEmpty || key.isEmpty) {
    stderr.writeln(
      'Administrative credentials are missing. Set SUPABASE_URL and '
      'SUPABASE_SECRET_KEY, or run through the launcher that loads '
      '.env.admin.',
    );
    exitCode = 1;
    return;
  }

  final query = <String, String>{
    'select': 'created_at,user_email,operation,status,target_type,target_id,'
        'parent_image_id,duration_ms,platform,app_version,error_message,details',
    'order': 'created_at.desc',
    'limit': '${options.limit}',
    // Filters are omitted entirely when not supplied, so an absent option
    // widens the export rather than matching on an empty value.
    if (options.email != null) 'user_email': 'eq.${options.email}',
    if (options.operation != null) 'operation': 'eq.${options.operation}',
    if (options.status != null) 'status': 'eq.${options.status}',
    if (options.since != null) 'created_at': 'gte.${options.since}',
  };

  // PostgREST takes repeated parameters for a range, which a Map cannot hold,
  // so an upper bound is appended separately.
  var requestUrl = Uri.parse(
    '${url.replaceFirst(RegExp(r'/$'), '')}/rest/v1/user_activity_logs',
  ).replace(queryParameters: query).toString();

  if (options.until != null) {
    requestUrl = '$requestUrl&created_at=lt.${Uri.encodeComponent(options.until!)}';
  }

  final client = HttpClient();

  try {
    final request = await client.getUrl(Uri.parse(requestUrl));
    request.headers
      ..set('apikey', key)
      ..set('Authorization', 'Bearer $key');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln('Export failed (${response.statusCode}): $body');
      exitCode = 1;
      return;
    }

    final rows = (jsonDecode(body) as List).cast<Map<String, dynamic>>();

    if (rows.isEmpty) {
      stdout.writeln('No rows matched. Nothing was written.');
      return;
    }

    final path = options.outputPath ?? _defaultPath(json: options.asJson);
    final file = File(path);

    await file.writeAsString(
      options.asJson
          ? const JsonEncoder.withIndent('  ').convert(rows)
          : _toCsv(rows),
    );

    stdout.writeln('Wrote ${rows.length} rows to ${file.absolute.path}');

    if (rows.length >= options.limit) {
      stdout.writeln(
        'Reached the limit of ${options.limit}, so older rows were left out. '
        'Raise --limit or narrow the range with --since.',
      );
    }
  } finally {
    client.close();
  }
}

/// Columns in a fixed order, so exports stay comparable between runs.
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

String _toCsv(List<Map<String, dynamic>> rows) {
  final buffer = StringBuffer()..writeln(_columns.join(','));

  for (final row in rows) {
    buffer.writeln(_columns.map((column) => _csvCell(row[column])).join(','));
  }

  return buffer.toString();
}

/// Quotes every cell rather than only those that need it: details is nested
/// JSON full of commas and quotes, and a spreadsheet mangles it otherwise.
String _csvCell(Object? value) {
  if (value == null) return '""';

  final text = value is Map || value is List ? jsonEncode(value) : '$value';

  return '"${text.replaceAll('"', '""')}"';
}

String _defaultPath({required bool json}) {
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;

  return 'activity-log-$stamp.${json ? 'json' : 'csv'}';
}

class _Options {
  const _Options({
    this.email,
    this.operation,
    this.status,
    this.since,
    this.until,
    this.outputPath,
    this.limit = 1000,
    this.asJson = false,
    this.showHelp = false,
  });

  final String? email;
  final String? operation;
  final String? status;
  final String? since;
  final String? until;
  final String? outputPath;
  final int limit;
  final bool asJson;
  final bool showHelp;

  static _Options parse(List<String> arguments) {
    String? valueFor(String name) {
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

    final limit = int.tryParse(valueFor('limit') ?? '') ?? 1000;

    return _Options(
      email: valueFor('email'),
      operation: valueFor('operation'),
      status: valueFor('status'),
      since: valueFor('since'),
      until: valueFor('until'),
      outputPath: valueFor('out'),
      limit: limit < 1 ? 1000 : limit,
      asJson: arguments.contains('--json'),
      showHelp: arguments.contains('--help') || arguments.contains('-h'),
    );
  }
}

const _usage = '''
Export user activity to a file. Every filter is optional and they combine.

  dart run tool/export_activity_log.dart [options]

  --email <address>     only this user
  --operation <name>    login, image_upload, image_full_view, sketch_edit, ...
  --status <state>      started | succeeded | failed | cancelled
  --since <date>        ISO date or timestamp, inclusive
  --until <date>        ISO date or timestamp, exclusive
  --limit <n>           maximum rows (default 1000)
  --out <path>          output file (default activity-log-<timestamp>.csv)
  --json                write JSON instead of CSV
  -h, --help            show this

Examples

  Everything recent:
    dart run tool/export_activity_log.dart

  One user's failures this month:
    dart run tool/export_activity_log.dart --email someone@example.com \\
      --status failed --since 2026-08-01

  Every image view, to inspect the ones that never succeeded:
    dart run tool/export_activity_log.dart --operation image_full_view --json

Requires SUPABASE_URL and SUPABASE_SECRET_KEY in the environment, as the
administration console does.
''';
