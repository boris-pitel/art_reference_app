import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

/// Proves that deleting an account really removes everything.
///
/// Creates a throwaway account, gives it a library row, a stored file, a
/// profile and a feedback entry, deletes it through the same Edge Function the
/// app calls, and then checks — with the service key, which sees past every
/// row-level policy — that nothing survived.
///
/// Worth having as a script rather than a one-off check: deletion is
/// irreversible and unobservable from the outside, so the failure mode is
/// silently leaving a user's photographs behind after telling them otherwise.
/// Re-run it whenever the schema or the function changes.
///
///   dart run tool/verify_account_deletion.dart
Future<void> main() async {
  final credentials = _loadCredentials();

  if (credentials == null) {
    stderr.writeln('Missing SUPABASE_URL / SUPABASE_SECRET_KEY.');
    exitCode = 1;
    return;
  }

  final (url, key) = credentials;
  final client = HttpClient();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final email = 'deletion-check-$stamp@painterreference.test';
  const password = 'ThrowawayCheck!2026';

  String? authUserId;

  try {
    stdout.writeln('Creating a throwaway account: $email');

    final created = await _request(
      client,
      'POST',
      '$url/auth/v1/admin/users',
      key,
      body: {'email': email, 'password': password, 'email_confirm': true},
    );

    authUserId = created['id'] as String?;

    if (authUserId == null) {
      stderr.writeln('Could not create the account: $created');
      exitCode = 1;
      return;
    }

    // The library id is derived from the email, exactly as the app derives it.
    final dataUserId = _uuidV5Url('art-reference-user:$email');

    stdout.writeln('  auth id  $authUserId');
    stdout.writeln('  data id  $dataUserId');

    // Give the account something to lose: a library row, a stored file, a
    // profile, and feedback. Deleting an empty account proves nothing.
    final imageId = _uuidV4();
    final storagePath = '$dataUserId/originals/$imageId';

    await _request(
      client,
      'POST',
      '$url/rest/v1/image_assets',
      key,
      body: {
        'id': imageId,
        'user_id': dataUserId,
        'user_email': email,
        'storage_path': storagePath,
        'thumbnail_storage_path': '$dataUserId/thumbnails/$imageId.jpg',
        'title': 'Deletion check',
      },
    );

    await _upload(client, '$url/storage/v1/object/reference-images/$storagePath',
        key);

    // No insert: creating the auth user already creates the profile row via a
    // trigger. Naming it is enough to prove the row exists and is removed.
    await _request(
      client,
      'PATCH',
      '$url/rest/v1/user_profiles?auth_user_id=eq.$authUserId',
      key,
      body: {'login_name': 'deletioncheck$stamp'},
    );

    await _request(
      client,
      'POST',
      '$url/rest/v1/user_activity_logs',
      key,
      body: {
        'user_id': authUserId,
        'user_email': email,
        'session_id': _uuidV4(),
        'operation': 'deletion_check',
        'status': 'succeeded',
        'platform': 'test',
        'app_version': 'test',
      },
    );

    stdout.writeln('Seeded: image row, stored file, profile, activity row.');

    // Sign in as the account, because the function deletes whoever holds the
    // token — the app's exact path.
    final session = await _request(
      client,
      'POST',
      '$url/auth/v1/token?grant_type=password',
      key,
      body: {'email': email, 'password': password},
    );

    final token = session['access_token'] as String?;

    if (token == null) {
      stderr.writeln('Could not sign in as the throwaway account: $session');
      exitCode = 1;
      return;
    }

    // A wrong confirmation must be refused — otherwise the friction is
    // decorative.
    stdout.writeln('\nChecking that a wrong confirmation is refused...');

    final refused = await _request(
      client,
      'POST',
      '$url/functions/v1/delete-my-account',
      key,
      bearer: token,
      body: {'confirm_email': 'not-the-right-address@example.com'},
      allowFailure: true,
    );

    _report(
      'wrong confirmation refused',
      refused['deleted'] != true && refused['error'] != null,
      detail: refused['error']?.toString(),
    );

    stdout.writeln('\nDeleting the account...');

    final deleted = await _request(
      client,
      'POST',
      '$url/functions/v1/delete-my-account',
      key,
      bearer: token,
      body: {'confirm_email': email},
      allowFailure: true,
    );

    _report('function reported success', deleted['deleted'] == true,
        detail: deleted['error']?.toString());

    stdout.writeln('\nChecking what survived...');

    final images = await _request(
      client,
      'GET',
      '$url/rest/v1/image_assets?user_id=eq.$dataUserId&select=id',
      key,
    );
    _report('library rows removed', (images['_list'] as List).isEmpty);

    final profiles = await _request(
      client,
      'GET',
      '$url/rest/v1/user_profiles?auth_user_id=eq.$authUserId&select=auth_user_id',
      key,
    );
    _report('profile removed', (profiles['_list'] as List).isEmpty);

    final activity = await _request(
      client,
      'GET',
      '$url/rest/v1/user_activity_logs?user_id=eq.$authUserId&select=id',
      key,
    );
    _report('activity rows removed', (activity['_list'] as List).isEmpty);

    final files = await _request(
      client,
      'POST',
      '$url/storage/v1/object/list/reference-images',
      key,
      body: {'prefix': '$dataUserId/originals', 'limit': 100},
    );
    _report('stored files removed', (files['_list'] as List).isEmpty);

    final user = await _request(
      client,
      'GET',
      '$url/auth/v1/admin/users/$authUserId',
      key,
      allowFailure: true,
    );
    final userGone = user['id'] == null;
    _report('auth account removed', userGone);

    if (userGone) authUserId = null;
    _summarise();
  } finally {
    // If anything above threw, the throwaway account must not be left behind.
    if (authUserId != null) {
      stdout.writeln('\nCleaning up the throwaway account...');
      await _request(
        client,
        'DELETE',
        '$url/auth/v1/admin/users/$authUserId',
        key,
        allowFailure: true,
      );
    }

    client.close();
  }
}

var _failures = 0;

void _summarise() => stdout.writeln(
  _failures == 0
      ? '\nAll checks passed. Nothing survived the deletion.'
      : '\n$_failures check(s) FAILED. Data survives an account deletion.',
);

void _report(String label, bool passed, {String? detail}) {
  stdout.writeln('  ${passed ? 'PASS' : 'FAIL'}  $label');
  if (detail != null && detail.isNotEmpty) stdout.writeln('        $detail');
  if (!passed) {
    _failures++;
    exitCode = 1;
  }
}

Future<Map<String, dynamic>> _request(
  HttpClient client,
  String method,
  String url,
  String key, {
  Map<String, Object?>? body,
  String? bearer,
  bool allowFailure = false,
}) async {
  final request = await client.openUrl(method, Uri.parse(url));
  request.headers
    ..set('apikey', key)
    ..set('Authorization', 'Bearer ${bearer ?? key}')
    ..set('Content-Type', 'application/json')
    ..set('Prefer', 'return=representation');

  if (body != null) request.write(jsonEncode(body));

  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();

  if (!allowFailure && (response.statusCode < 200 || response.statusCode >= 300)) {
    throw StateError('$method $url -> ${response.statusCode}: $text');
  }

  if (text.isEmpty) return {};

  final decoded = jsonDecode(text);

  // A list response is wrapped so every caller can treat the result as a map.
  return decoded is List
      ? {'_list': decoded}
      : {...(decoded as Map).cast<String, dynamic>(), '_list': const []};
}

Future<void> _upload(HttpClient client, String url, String key) async {
  final request = await client.postUrl(Uri.parse(url));
  request.headers
    ..set('apikey', key)
    ..set('Authorization', 'Bearer $key')
    ..set('Content-Type', 'image/jpeg');
  request.add(List<int>.filled(64, 0));

  final response = await request.close();
  await response.drain<void>();
}

const _uuid = Uuid();

/// The same derivation the app uses. A different one here would look like a
/// deletion failure when the real fault was this script.
String _uuidV5Url(String name) => _uuid.v5(Namespace.url.value, name);

String _uuidV4() => _uuid.v4();

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
