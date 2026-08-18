import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the app is currently withheld from normal use.
class AppStatus {
  const AppStatus({required this.maintenanceEnabled, this.message});

  final bool maintenanceEnabled;
  final String? message;

  /// The state assumed whenever the real status cannot be determined.
  static const available = AppStatus(maintenanceEnabled: false);

  factory AppStatus.fromResponse(Object? data) {
    if (data is! Map) return available;

    final message = data['message'];

    return AppStatus(
      maintenanceEnabled: data['maintenance_enabled'] == true,
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : null,
    );
  }
}

class AppStatusService {
  const AppStatusService(this._client);

  final SupabaseClient _client;

  /// Kept short: this runs on the launch path, and a slow status service must
  /// not become a slow app.
  static const _timeout = Duration(seconds: 4);

  Future<AppStatus> load() async {
    try {
      final response = await _client.functions
          .invoke('get-app-status')
          .timeout(_timeout);

      return AppStatus.fromResponse(response.data);
    } catch (_) {
      // Fail open. A status lookup that errors, times out, or hits an
      // unreachable backend must never be able to lock every user out — that
      // failure would be worse than the outage the gate exists to announce.
      return AppStatus.available;
    }
  }
}
