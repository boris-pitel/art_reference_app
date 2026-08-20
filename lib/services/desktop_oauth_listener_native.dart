import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A short-lived local web server that catches the OAuth redirect on desktop.
///
/// Desktop has no deep links, so Supabase is told to redirect to a loopback
/// address instead. This listens there just long enough to read the
/// authorisation code out of the query string, then shuts down.
class DesktopOAuthListener {
  DesktopOAuthListener({required this.port});

  final int port;

  HttpServer? _server;

  /// Completes with the authorisation code, or null if the user abandoned the
  /// sign-in or it failed. Waiting forever would leave the port held and the
  /// caller stuck, so it gives up after five minutes.
  Future<String?> start() async {
    final completer = Completer<String?>();

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } catch (error) {
      debugPrint('[OAUTH] could not listen on $port: $error');
      return null;
    }

    unawaited(
      _server!.first.then((request) async {
        final code = request.uri.queryParameters['code'];
        final error = request.uri.queryParameters['error'];

        // The browser stays open on whatever we return, so it has to say
        // something — an empty response looks like a failure.
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_resultPage(succeeded: code != null && error == null));

        await request.response.close();

        if (!completer.isCompleted) completer.complete(code);
      }).catchError((Object error) {
        if (!completer.isCompleted) completer.complete(null);
      }),
    );

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static String _resultPage({required bool succeeded}) {
    final message = succeeded
        ? 'You are signed in. You can close this tab and return to Painter '
              'Reference.'
        : 'Sign-in did not complete. Close this tab and try again in Painter '
              'Reference.';

    return '''
<!DOCTYPE html>
<html>
  <head><meta charset="utf-8"><title>Painter Reference</title></head>
  <body style="font-family: system-ui, sans-serif; margin: 3rem; color: #191524">
    <p style="font-size: 1.05rem">$message</p>
  </body>
</html>
''';
  }
}
