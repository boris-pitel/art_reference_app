// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

/// Device facts for the web build, read from the browser.
///
/// The user agent alone is not enough: Chrome's User-Agent Reduction freezes
/// the Android version at 10 and replaces the model with "K", so a report from
/// a modern phone is indistinguishable from any other. The real model comes
/// from User-Agent Client Hints, which have to be requested explicitly.
class DeviceProfile {
  const DeviceProfile._();

  static Map<String, Object?>? _cached;

  static Future<Map<String, Object?>> load() async {
    return _cached ??= {..._readNavigator(), ...await _readClientHints()};
  }

  /// Whatever has been resolved so far. Falls back to the navigator fields
  /// alone if called before [load] finishes — logging never waits.
  static Map<String, Object?> get current => _cached ?? _readNavigator();

  static Map<String, Object?> _readNavigator() {
    try {
      final navigator = html.window.navigator;

      return {
        'user_agent': navigator.userAgent,
        'platform': navigator.platform,
        'language': navigator.language,
        'hardware_concurrency': navigator.hardwareConcurrency,
        'max_touch_points': navigator.maxTouchPoints,
        'device_pixel_ratio': html.window.devicePixelRatio,
        'screen': '${html.window.screen?.width}x${html.window.screen?.height}',
      };
    } catch (_) {
      return const {};
    }
  }

  /// The values the reduced user agent hides. Chromium only; other browsers
  /// have no userAgentData and keep whatever their user agent already says.
  static Future<Map<String, Object?>> _readClientHints() async {
    try {
      if (!_navigator.has('userAgentData')) return const {};

      final agentData = _navigator.getProperty<JSObject>('userAgentData'.toJS);

      final requested = <String>[
        'model',
        'platformVersion',
        'architecture',
        'bitness',
      ].map((hint) => hint.toJS).toList().toJS;

      final values = await agentData
          .callMethod<JSPromise<JSObject>>(
            'getHighEntropyValues'.toJS,
            requested,
          )
          .toDart;

      return {
        'model': values.getProperty<JSString?>('model'.toJS)?.toDart,
        'platform_version': values
            .getProperty<JSString?>('platformVersion'.toJS)
            ?.toDart,
        'architecture': values
            .getProperty<JSString?>('architecture'.toJS)
            ?.toDart,
      };
    } catch (_) {
      return const {};
    }
  }
}
