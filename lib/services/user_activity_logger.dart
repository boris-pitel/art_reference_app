import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_version.dart';
import 'device_profile.dart';
import 'package:uuid/uuid.dart';

class UserActivityLogger {
  UserActivityLogger._();

  static final UserActivityLogger instance = UserActivityLogger._();

  /// A session is one sitting, not one process.
  ///
  /// This was generated once per launch, which is fine on the web where a
  /// reload starts a new one, and useless on Windows or Android where the app
  /// can stay open for days — a week of activity under a single id groups too
  /// much to tell you anything. It now restarts after a gap, so the id means
  /// "what this person did in one go", which is the unit you actually want
  /// when reconstructing what led up to a failure.
  static const _sessionGap = Duration(minutes: 30);

  String _sessionId = const Uuid().v4();
  DateTime _lastActivity = DateTime.now();

  String get sessionId {
    final now = DateTime.now();
    final elapsed = now.difference(_lastActivity);

    // A negative gap means the clock moved backwards; treat it as a new
    // sitting rather than trusting arithmetic on a clock that just jumped.
    if (elapsed.isNegative || elapsed > _sessionGap) {
      _sessionId = const Uuid().v4();
    }

    _lastActivity = now;

    return _sessionId;
  }

  String get _platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  /// Where a finished entry goes, when it should not go to the database.
  ///
  /// Exists so the logging itself can be tested: without it a test would have
  /// to stand up Supabase, and the alternative — asserting against a copy of
  /// this logic — proves only that the copy is self-consistent.
  @visibleForTesting
  Future<void> Function(Map<String, Object?> entry)? sink;

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
      final testSink = sink;

      if (testSink != null) {
        await testSink({
          'operation': operation,
          'status': status,
          'target_type': targetType,
          'target_id': targetId,
          'duration_ms': durationMs,
          'details': details,
          if (error != null) 'error_message': _sanitizeError(error),
        });
        return;
      }

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

  /// Runs [action], recording `started` before it and `succeeded`/`failed`
  /// after, with how long it took.
  ///
  /// Logging used to be added a line at a time, which is why most operations
  /// recorded only their success: the failure paths were easy to forget, and a
  /// tap that died partway through left no row at all. Wrapping the work means
  /// the three outcomes cannot drift apart — and a `started` with no matching
  /// end becomes evidence in itself, which is the only way a silent failure
  /// shows up in a query.
  ///
  /// The error is re-thrown, so existing handling is unaffected.
  Future<T> trace<T>({
    required String operation,
    required Future<T> Function() action,
    String? targetType,
    String? targetId,
    String? parentImageId,
    Map<String, Object?> details = const {},
    // Not every completion is a success: a save the user backs out of is a
    // cancellation, and recording it as either a success or a failure would
    // misreport what happened.
    String Function(T result)? outcome,
  }) async {
    record(
      operation: operation,
      status: 'started',
      targetType: targetType,
      targetId: targetId,
      parentImageId: parentImageId,
      details: details,
    );

    final stopwatch = Stopwatch()..start();

    try {
      final result = await action();

      record(
        operation: operation,
        status: outcome?.call(result) ?? 'succeeded',
        targetType: targetType,
        targetId: targetId,
        parentImageId: parentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: details,
      );

      return result;
    } catch (error) {
      record(
        operation: operation,
        status: 'failed',
        targetType: targetType,
        targetId: targetId,
        parentImageId: parentImageId,
        durationMs: stopwatch.elapsedMilliseconds,
        details: details,
        error: error,
      );

      rethrow;
    }
  }

  String _sanitizeError(Object error) {
    var value = error.toString();
    value = value.replaceAll(RegExp(r'https?://\S+'), '[url removed]');
    return value.length <= 1000 ? value : value.substring(0, 1000);
  }
}
