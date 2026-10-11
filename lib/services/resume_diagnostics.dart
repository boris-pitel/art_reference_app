import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';

/// Local, bounded diagnostics. Never records route arguments or user data.
class ResumeDiagnostics extends NavigatorObserver {
  static final instance = ResumeDiagnostics();
  static const storageKey = 'resume_diagnostics_v1';
  final runId = DateTime.now().microsecondsSinceEpoch.toString();
  final List<String> _entries = [];
  Future<void> _writes = Future.value();

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    _entries.addAll(preferences.getStringList(storageKey) ?? []);
    record('launch version=$appVersion');
    await _writes;
  }

  void record(String event) {
    _entries.add(
      '${DateTime.now().toUtc().toIso8601String()} run=$runId $event',
    );
    if (_entries.length > 300) _entries.removeRange(0, _entries.length - 300);
    final snapshot = List<String>.of(_entries);
    _writes = _writes
        .then((_) async {
          await (await SharedPreferences.getInstance()).setStringList(
            storageKey,
            snapshot,
          );
        })
        .catchError((Object _) {});
  }

  String export() => _entries.join('\n');

  String _route(Route<dynamic>? route) => route == null
      ? 'none'
      : '${route.runtimeType}#${identityHashCode(route)}';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      record('navigation push ${_route(route)} from=${_route(previousRoute)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      record('navigation pop ${_route(route)} to=${_route(previousRoute)}');

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      record('navigation remove ${_route(route)}');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      record('navigation replace ${_route(oldRoute)} with=${_route(newRoute)}');
}
