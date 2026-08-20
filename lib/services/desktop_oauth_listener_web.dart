/// The web build never listens for a redirect — the browser handles it.
class DesktopOAuthListener {
  DesktopOAuthListener({required this.port});

  final int port;

  Future<String?> start() async => null;

  Future<void> stop() async {}
}
