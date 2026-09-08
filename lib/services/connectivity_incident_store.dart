import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'user_activity_logger.dart';

/// Retains backend failures until Supabase is reachable again.
///
/// Writing directly to the activity table during the failure would only cause
/// another timeout. The first later successful app request triggers [flush].
class ConnectivityIncidentStore {
  const ConnectivityIncidentStore._();

  static const String _key = 'pending_connectivity_incidents_v1';
  static const int _maximumEntries = 20;
  static Future<void> _serial = Future<void>.value();

  static Future<void> record(Object error) => _enqueue(() async {
    final preferences = await SharedPreferences.getInstance();
    final entries = _read(preferences);
    var message = error.toString();
    if (message.length > 1000) message = message.substring(0, 1000);
    entries.add({
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
      'error': message,
    });
    final retained = entries.length <= _maximumEntries
        ? entries
        : entries.sublist(entries.length - _maximumEntries);
    await preferences.setString(_key, jsonEncode(retained));
  });

  static Future<void> flush() => _enqueue(() async {
    final preferences = await SharedPreferences.getInstance();
    final entries = _read(preferences);
    if (entries.isEmpty) return;

    var stored = 0;
    for (final entry in entries) {
      final succeeded = await UserActivityLogger.instance.log(
        operation: 'supabase_connectivity',
        status: 'failed',
        targetType: 'backend',
        details: {
          'recorded_at': entry['recorded_at']?.toString(),
          'recovered_at': DateTime.now().toUtc().toIso8601String(),
          'replayed_after_recovery': true,
        },
        error: entry['error']?.toString() ?? 'Unknown backend failure',
      );
      if (!succeeded) break;
      stored++;
    }

    if (stored == 0) return;
    if (stored == entries.length) {
      await preferences.remove(_key);
    } else {
      await preferences.setString(_key, jsonEncode(entries.sublist(stored)));
    }
  });

  static Future<void> _enqueue(Future<void> Function() action) {
    final next = _serial.catchError((_) {}).then((_) => action());
    _serial = next;
    return next;
  }

  static List<Map<String, dynamic>> _read(SharedPreferences preferences) {
    final value = preferences.getString(_key);
    if (value == null) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
