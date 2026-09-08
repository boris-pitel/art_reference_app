import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'connectivity_incident_store.dart';

enum BackendConnectivityState {
  unknown,
  online,
  noInternet,
  backendUnavailable,
}

/// App-wide connectivity state.
///
/// Generic connectivity is event-driven through the operating system. This
/// class never polls or pings Supabase. A backend-specific failure is reported
/// only by a real app request that was already needed for the user's action.
class ConnectivityMonitor extends ChangeNotifier {
  ConnectivityMonitor._();

  static final ConnectivityMonitor instance = ConnectivityMonitor._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  BackendConnectivityState _state = BackendConnectivityState.unknown;
  String? _details;
  Set<ConnectivityResult> _interfaces = const {};

  BackendConnectivityState get state => _state;
  String? get details => _details;
  bool get isOffline =>
      _state == BackendConnectivityState.noInternet ||
      _state == BackendConnectivityState.backendUnavailable;

  Future<void> start() async {
    if (_subscription != null) return;
    final connectivity = Connectivity();
    try {
      _applyInterfaces(await connectivity.checkConnectivity());
      _subscription = connectivity.onConnectivityChanged.listen(
        _applyInterfaces,
        onError: (Object error) {
          debugPrint('[CONNECTIVITY] Native listener failed: $error');
        },
      );
    } catch (error) {
      debugPrint('[CONNECTIVITY] Native status unavailable: $error');
      _setState(BackendConnectivityState.unknown, error.toString());
    }
  }

  Future<void> checkNow() async {
    _applyInterfaces(await Connectivity().checkConnectivity());
  }

  void _applyInterfaces(List<ConnectivityResult> interfaces) {
    final nextInterfaces = interfaces.toSet();
    final pathChanged = !setEquals(_interfaces, nextInterfaces);
    _interfaces = nextInterfaces;
    final connected = interfaces.any(
      (result) => result != ConnectivityResult.none,
    );
    if (!connected) {
      _setState(
        BackendConnectivityState.noInternet,
        'The operating system reports no network connection.',
      );
      return;
    }

    // A new network path makes a normal request worth trying again. This is
    // not a claim that Supabase is healthy; only a successful real request can
    // prove that.
    if (_state == BackendConnectivityState.unknown ||
        _state == BackendConnectivityState.noInternet ||
        (_state == BackendConnectivityState.backendUnavailable &&
            pathChanged)) {
      _setState(BackendConnectivityState.online, null);
    }
  }

  /// Called by a normal Supabase operation after it encounters a network or
  /// service error. No extra health request is made.
  void reportBackendFailure(Object error) {
    if (_state == BackendConnectivityState.noInternet) return;
    if (_state != BackendConnectivityState.backendUnavailable) {
      unawaited(ConnectivityIncidentStore.record(error));
    }
    _setState(BackendConnectivityState.backendUnavailable, error.toString());
  }

  /// Called after a normal Supabase operation succeeds.
  void reportBackendSuccess() {
    if (_state == BackendConnectivityState.noInternet) return;
    _setState(BackendConnectivityState.online, null);
    unawaited(ConnectivityIncidentStore.flush());
  }

  /// Lets an explicit user retry perform the next normal Supabase operation.
  /// This changes no network state and sends no request by itself.
  void prepareBackendRetry() {
    if (_state == BackendConnectivityState.backendUnavailable) {
      _setState(BackendConnectivityState.online, null);
    }
  }

  void _setState(BackendConnectivityState next, String? details) {
    _details = details;
    if (_state == next) return;
    debugPrint(
      '[CONNECTIVITY] ${_state.name} -> ${next.name}'
      '${details == null ? '' : ': $details'}',
    );
    _state = next;
    notifyListeners();
  }

  @visibleForTesting
  void setForTesting(BackendConnectivityState value) {
    _setState(value, null);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}

class NetworkAvailability {
  const NetworkAvailability._();

  static bool isNetworkFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('networkerror') ||
        text.contains('failed to fetch') ||
        text.contains('xmlhttprequest error') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('no address associated with hostname') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('service unavailable') ||
        text.contains('status: 502') ||
        text.contains('status: 503') ||
        text.contains('status: 504') ||
        RegExp(r'status(?:code)?\s*[:=]\s*5\d\d').hasMatch(text);
  }
}
