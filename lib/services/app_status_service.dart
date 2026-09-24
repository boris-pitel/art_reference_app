import 'package:supabase_flutter/supabase_flutter.dart';

import 'network_availability.dart';

/// Whether the app is currently withheld from normal use.
class AppStatus {
  const AppStatus({
    required this.maintenanceEnabled,
    this.message,
    this.announcement,
  });

  final bool maintenanceEnabled;
  final String? message;
  final AppAnnouncement? announcement;

  /// The state assumed whenever the real status cannot be determined.
  static const available = AppStatus(maintenanceEnabled: false);

  factory AppStatus.fromResponse(Object? data) {
    if (data is! Map) return available;

    final message = data['message'];
    final announcementId = data['announcement_id'];
    final announcementTitle = data['announcement_title'];
    final announcementMessage = data['announcement_message'];

    return AppStatus(
      maintenanceEnabled: data['maintenance_enabled'] == true,
      message: message is String && message.trim().isNotEmpty
          ? message.trim()
          : null,
      announcement:
          announcementId is String &&
              announcementTitle is String &&
              announcementTitle.trim().isNotEmpty &&
              announcementMessage is String &&
              announcementMessage.trim().isNotEmpty
          ? AppAnnouncement(
              id: announcementId,
              title: announcementTitle.trim(),
              message: announcementMessage.trim(),
            )
          : null,
    );
  }
}

class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.message,
  });

  final String id;
  final String title;
  final String message;
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

      ConnectivityMonitor.instance.reportBackendSuccess();
      return AppStatus.fromResponse(response.data);
    } catch (error) {
      if (NetworkAvailability.isNetworkFailure(error)) {
        ConnectivityMonitor.instance.reportBackendFailure(error);
      }
      // Fail open. A status lookup that errors, times out, or hits an
      // unreachable backend must never be able to lock every user out — that
      // failure would be worse than the outage the gate exists to announce.
      return AppStatus.available;
    }
  }
}
