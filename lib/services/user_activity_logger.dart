import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_version.dart';
import 'device_profile.dart';
import 'package:uuid/uuid.dart';

class UserActivityLogger {
  UserActivityLogger._();

  static final UserActivityLogger instance = UserActivityLogger._();
  final String sessionId = const Uuid().v4();

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<void> log({
    required String operation,
    required String status,
    String? targetType,
    String? targetId,
    String? parentImageId,
    int? durationMs,
    Map<String, Object?> details = const {},
    Object? error,
  }) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      final email = user?.email?.trim().toLowerCase();
      if (user == null || email == null || email.isEmpty) return;
      await client.from('user_activity_logs').insert({
        'user_id': user.id,
        'user_email': email,
        'session_id': sessionId,
        'operation': operation,
        'status': status,
        'target_type': targetType,
        'target_id': targetId,
        'parent_image_id': parentImageId,
        'duration_ms': durationMs,
        'platform': _platform,
        'app_version': appVersion,
        // Device facts ride along with every entry so a report that only
        // reproduces on one person's hardware can be traced to that hardware.
        'details': {...details, 'device': DeviceProfile.current},
        if (error != null) 'error_message': _sanitizeError(error),
      });
    } catch (loggingError) {
      debugPrint(
        '[ACTIVITY LOG] $operation/$status could not be stored: $loggingError',
      );
    }
  }

  void record({
    required String operation,
    required String status,
    String? targetType,
    String? targetId,
    String? parentImageId,
    int? durationMs,
    Map<String, Object?> details = const {},
    Object? error,
  }) {
    unawaited(
      log(
        operation: operation,
        status: status,
        targetType: targetType,
        targetId: targetId,
        parentImageId: parentImageId,
        durationMs: durationMs,
        details: details,
        error: error,
      ),
    );
  }

  String _sanitizeError(Object error) {
    var value = error.toString();
    value = value.replaceAll(RegExp(r'https?://\S+'), '[url removed]');
    return value.length <= 1000 ? value : value.substring(0, 1000);
  }
}
