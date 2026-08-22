import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A minimal S3 client for Cloudflare R2, signed with AWS Signature V4.
///
/// Mirrors supabase/functions/_shared/r2.ts, which does the same job inside an
/// Edge Function. Two implementations exist because one runs in Deno and one
/// in Dart; they are deliberately kept to the same four operations so that a
/// difference in behaviour between them would be obvious rather than subtle.
class R2Client {
  R2Client({
    required this.accountId,
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.bucket,
  });

  final String accountId;
  final String accessKeyId;
  final String secretAccessKey;
  final String bucket;

  static const _region = 'auto';
  static const _service = 's3';

  final HttpClient _client = HttpClient();

  String get host => '$accountId.r2.cloudflarestorage.com';

  void close() => _client.close();

  /// Loads configuration from the environment, falling back to .env.admin.
  static R2Client? fromEnvironment() {
    final values = <String, String>{};

    for (final name in const [
      'R2_ACCOUNT_ID',
      'R2_ACCESS_KEY_ID',
      'R2_SECRET_ACCESS_KEY',
      'R2_BUCKET',
    ]) {
      final value = Platform.environment[name]?.trim();
      if (value != null && value.isNotEmpty) values[name] = value;
    }

    final file = File('.env.admin');

    if (file.existsSync()) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        final separator = trimmed.indexOf('=');
        if (separator <= 0) continue;

        final name = trimmed.substring(0, separator).trim();
        if (!name.startsWith('R2_')) continue;

        values.putIfAbsent(
          name,
          () => trimmed
              .substring(separator + 1)
              .trim()
              .replaceAll(RegExp(r'''^["']|["']$'''), ''),
        );
      }
    }

    if (values.length < 4) return null;

    return R2Client(
      accountId: values['R2_ACCOUNT_ID']!,
      accessKeyId: values['R2_ACCESS_KEY_ID']!,
      secretAccessKey: values['R2_SECRET_ACCESS_KEY']!,
      bucket: values['R2_BUCKET']!,
    );
  }

  String _sha256Hex(List<int> data) => sha256.convert(data).toString();

  List<int> _hmac(List<int> key, String message) =>
      Hmac(sha256, key).convert(utf8.encode(message)).bytes;

  /// Path segments are encoded individually so slashes survive as separators.
  String _encodeKey(String key) =>
      key.split('/').map(Uri.encodeComponent).join('/');

  Future<HttpClientResponse> _send(
    String method,
    String key, {
    List<int>? body,
    Map<String, String> query = const {},
    String? contentType,
  }) async {
    final path = '/$bucket${key.isEmpty ? '' : '/${_encodeKey(key)}'}';

    // Query parameters must be sorted for the canonical request or the
    // signature will not match the one the server computes.
    final sortedKeys = query.keys.toList()..sort();
    final canonicalQuery = sortedKeys
        .map(
          (k) =>
              '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(query[k]!)}',
        )
        .join('&');

    final now = DateTime.now().toUtc();
    // Every fractional digit must go, not a fixed three: Dart emits
    // microseconds when they are non-zero, so stripping three left the rest
    // behind and produced a timestamp the signature did not match. JavaScript
    // always emits exactly three, which is why the same approach worked there.
    final amzDate = now
        .toIso8601String()
        .replaceAll(RegExp(r'[:\-]'), '')
        .replaceAll(RegExp(r'\.\d+'), '');
    final stamp = amzDate.substring(0, 8);
    final payload = body ?? const <int>[];
    final payloadHash = _sha256Hex(payload);

    final headers = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
    };

    if (contentType != null) headers['content-type'] = contentType;

    final names = headers.keys.toList()..sort();
    final canonicalHeaders =
        names.map((n) => '$n:${headers[n]!.trim()}\n').join();
    final signedHeaders = names.join(';');

    final canonicalRequest = [
      method,
      path,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final scope = '$stamp/$_region/$_service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      _sha256Hex(utf8.encode(canonicalRequest)),
    ].join('\n');

    var signingKey = _hmac(utf8.encode('AWS4$secretAccessKey'), stamp);
    signingKey = _hmac(signingKey, _region);
    signingKey = _hmac(signingKey, _service);
    signingKey = _hmac(signingKey, 'aws4_request');

    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    final uri = Uri.parse(
      'https://$host$path${canonicalQuery.isEmpty ? '' : '?$canonicalQuery'}',
    );

    final request = await _client.openUrl(method, uri);

    // Set explicitly, or Dart streams the body with chunked transfer encoding
    // and R2 rejects the request with 411 MissingContentLength. Node's fetch
    // sets this itself, which is why the same code signed and sent correctly
    // there.
    request.contentLength = payload.length;

    headers.forEach((name, value) {
      if (name != 'host') request.headers.set(name, value);
    });

    request.headers.set(
      'Authorization',
      'AWS4-HMAC-SHA256 Credential=$accessKeyId/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    );

    if (body != null) request.add(body);

    return request.close();
  }

  Future<void> put(
    String key,
    List<int> body, {
    String contentType = 'application/octet-stream',
  }) async {
    final response = await _send(
      'PUT',
      key,
      body: body,
      contentType: contentType,
    );

    final text = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('PUT $key failed: ${response.statusCode} $text');
    }
  }

  /// Size of an object, or null when it is not there — without transferring it.
  Future<int?> head(String key) async {
    final response = await _send('HEAD', key);
    await response.drain<void>();

    if (response.statusCode == 404) return null;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HEAD $key failed: ${response.statusCode}');
    }

    return response.contentLength >= 0 ? response.contentLength : 0;
  }

  Future<List<int>?> get(String key) async {
    final response = await _send('GET', key);

    if (response.statusCode == 404) {
      await response.drain<void>();
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw StateError('GET $key failed: ${response.statusCode}');
    }

    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }

    return bytes;
  }

  Future<void> delete(String key) async {
    final response = await _send('DELETE', key);
    await response.drain<void>();

    // A missing object is the intended end state, so 404 is not a failure.
    if (response.statusCode >= 300 && response.statusCode != 404) {
      throw StateError('DELETE $key failed: ${response.statusCode}');
    }
  }

  /// Every key under a prefix, following continuation tokens.
  Future<Map<String, int>> list([String prefix = '']) async {
    final found = <String, int>{};
    String? token;

    do {
      final query = <String, String>{'list-type': '2', 'prefix': prefix};
      if (token != null) query['continuation-token'] = token;

      final response = await _send('GET', '', query: query);
      final xml = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('list failed: ${response.statusCode} $xml');
      }

      for (final match
          in RegExp(r'<Contents>([\s\S]*?)</Contents>').allMatches(xml)) {
        final block = match.group(1)!;
        final key = RegExp(r'<Key>([\s\S]*?)</Key>').firstMatch(block)?.group(1);
        final size =
            RegExp(r'<Size>(\d+)</Size>').firstMatch(block)?.group(1);

        if (key != null) {
          found[_unescape(key)] = int.tryParse(size ?? '0') ?? 0;
        }
      }

      token = RegExp(r'<NextContinuationToken>([\s\S]*?)</NextContinuationToken>')
          .firstMatch(xml)
          ?.group(1);
    } while (token != null);

    return found;
  }

  String _unescape(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"');
}
