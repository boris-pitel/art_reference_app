import 'dart:io';

class AdminConfig {
  const AdminConfig({
    required this.supabaseUrl,
    required this.secretKey,
    required this.passwordRedirectUrl,
  });

  final String supabaseUrl;
  final String secretKey;
  final String? passwordRedirectUrl;

  static AdminConfig fromEnvironment() {
    final environment = Platform.environment;
    final url = environment['SUPABASE_URL']?.trim() ?? '';
    final key =
        (environment['SUPABASE_SECRET_KEY'] ??
                environment['SUPABASE_SERVICE_ROLE_KEY'])
            ?.trim() ??
        '';
    final redirect = environment['SUPABASE_PASSWORD_REDIRECT_URL']?.trim();

    if (url.isEmpty || key.isEmpty) {
      throw StateError(
        'Administrative credentials are missing. Set SUPABASE_URL and '
        'SUPABASE_SECRET_KEY (or legacy SUPABASE_SERVICE_ROLE_KEY).',
      );
    }

    if (!Uri.parse(url).isAbsolute || !url.startsWith('https://')) {
      throw StateError('SUPABASE_URL must be an absolute HTTPS URL.');
    }

    return AdminConfig(
      supabaseUrl: url.replaceFirst(RegExp(r'/$'), ''),
      secretKey: key,
      passwordRedirectUrl: redirect == null || redirect.isEmpty
          ? null
          : redirect,
    );
  }
}
