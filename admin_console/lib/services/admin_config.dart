import 'dart:io';

class AdminConfig {
  const AdminConfig({
    required this.supabaseUrl,
    required this.secretKey,
    required this.passwordRedirectUrl,
    required this.sourcePath,
  });

  final String supabaseUrl;
  final String secretKey;
  final String? passwordRedirectUrl;
  final String sourcePath;

  static Future<AdminConfig> load() async {
    final values = <String, String>{};
    File? source;
    for (final candidate in _candidateFiles()) {
      if (await candidate.exists()) {
        source = candidate;
        for (final rawLine in await candidate.readAsLines()) {
          final line = rawLine.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final separator = line.indexOf('=');
          if (separator <= 0) continue;
          values[line.substring(0, separator).trim()] = line
              .substring(separator + 1)
              .trim();
        }
        break;
      }
    }

    final environment = Platform.environment;
    final url = (environment['SUPABASE_URL'] ?? values['SUPABASE_URL'] ?? '')
        .trim();
    final key =
        (environment['SUPABASE_SECRET_KEY'] ??
                environment['SUPABASE_SERVICE_ROLE_KEY'] ??
                values['SUPABASE_SECRET_KEY'] ??
                values['SUPABASE_SERVICE_ROLE_KEY'] ??
                '')
            .trim();
    final redirect =
        (environment['SUPABASE_PASSWORD_REDIRECT_URL'] ??
                values['SUPABASE_PASSWORD_REDIRECT_URL'])
            ?.trim();

    if (url.isEmpty || key.isEmpty) {
      throw StateError(
        'Administrative credentials are missing. Create .env.admin in the '
        'repository root or beside the executable and set SUPABASE_URL and '
        'SUPABASE_SECRET_KEY.',
      );
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.isAbsolute || parsed.scheme != 'https') {
      throw StateError('SUPABASE_URL must be an absolute HTTPS URL.');
    }

    return AdminConfig(
      supabaseUrl: url.replaceFirst(RegExp(r'/$'), ''),
      secretKey: key,
      passwordRedirectUrl: redirect == null || redirect.isEmpty
          ? null
          : redirect,
      sourcePath: source?.path ?? 'process environment',
    );
  }

  static List<File> _candidateFiles() {
    final paths = <String>{};
    void addParents(Directory start) {
      var current = start.absolute;
      // A Windows release lives under
      // admin_console/build/windows/x64/runner/Release, which is more than
      // six levels below the repository-level configuration file.
      for (var depth = 0; depth < 10; depth += 1) {
        paths.add('${current.path}${Platform.pathSeparator}.env.admin');
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }

    addParents(Directory.current);
    addParents(File(Platform.resolvedExecutable).parent);
    return paths.map(File.new).toList();
  }
}
