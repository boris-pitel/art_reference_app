import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_platform.dart';
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
              audienceKind: data['audience_kind'] as String? ?? 'all',
              targetUserIds:
                  (data['target_user_ids'] as List?)?.cast<String>() ??
                  const [],
              targetPlatforms:
                  (data['target_platforms'] as List?)?.cast<String>() ??
                  const [],
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
    this.publishedAt,
    this.audienceKind = 'all',
    this.targetUserIds = const [],
    this.targetPlatforms = const [],
  });

  final String id;
  final String title;
  final String message;
  final DateTime? publishedAt;
  final String audienceKind;
  final List<String> targetUserIds;
  final List<String> targetPlatforms;
}

class AppStatusService {
  const AppStatusService(this._client);

  final SupabaseClient _client;

  /// Kept short: this runs on the launch path, and a slow status service must
  /// not become a slow app.
  static const _timeout = Duration(seconds: 4);

  Future<List<AppAnnouncement>> recentAnnouncements() async {
    final response = await _client.functions.invoke(
      'list-app-announcements',
      body: {'platform': currentAppPlatform},
    );
    final data = response.data;
    if (data is! Map || data['announcements'] is! List) {
      throw StateError('Unable to load notifications.');
    }
    final rows = (data['announcements'] as List).cast<Map<String, dynamic>>();
    return rows
        .map(
          (row) => AppAnnouncement(
            id: row['id'] as String,
            title: row['title'] as String,
            message: row['message'] as String,
            publishedAt: DateTime.tryParse(
              row['published_at'] as String,
            )?.toLocal(),
          ),
        )
        .toList(growable: false);
  }

  Future<AppStatus> load() async {
    try {
      final response = await _client.functions
          .invoke('get-app-status', body: {'platform': currentAppPlatform})
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
