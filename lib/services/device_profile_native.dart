import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Device facts attached to activity logs.
///
/// Exists because a failure that only happens on one user's phone cannot be
/// reproduced or instrumented locally — without knowing which device reported
/// it, a log entry says nothing about why it failed there and not elsewhere.
class DeviceProfile {
  const DeviceProfile._();

  static Map<String, Object?>? _cached;

  /// Resolved once per launch; the values cannot change while the app runs.
  static Future<Map<String, Object?>> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final resolved = await _resolve();
    _cached = resolved;

    return resolved;
  }

  /// Whatever has been resolved so far, for callers that cannot wait. Empty
  /// until [load] has completed once — logging is never worth blocking on.
  static Map<String, Object?> get current => _cached ?? const {};

  static Future<Map<String, Object?>> _resolve() async {
    final plugin = DeviceInfoPlugin();

    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          return {
            'manufacturer': info.manufacturer,
            'model': info.model,
            'device': info.device,
            'android_version': info.version.release,
            'sdk_int': info.version.sdkInt,
            'is_physical_device': info.isPhysicalDevice,
            'supported_abis': info.supportedAbis,
          };

        case TargetPlatform.iOS:
          final info = await plugin.iosInfo;
          return {
            'model': info.utsname.machine,
            'system_name': info.systemName,
            'system_version': info.systemVersion,
            'is_physical_device': info.isPhysicalDevice,
          };

        case TargetPlatform.windows:
          final info = await plugin.windowsInfo;
          return {
            'computer_name': info.computerName,
            'build_number': info.buildNumber,
            'memory_mb': info.systemMemoryInMegabytes,
          };

        default:
          return const {};
      }
    } catch (error) {
      // Device details are diagnostic only. Failing to read them must never
      // interfere with the operation being logged.
      debugPrint('[DEVICE PROFILE] unavailable: $error');
      return const {};
    }
  }
}
