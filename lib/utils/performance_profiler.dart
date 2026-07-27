import 'package:flutter/foundation.dart';

class PerformanceProfiler {
  PerformanceProfiler(this.operationName)
    : _totalStopwatch = Stopwatch()..start(),
      _checkpointStopwatch = Stopwatch()..start();

  final String operationName;

  final Stopwatch _totalStopwatch;
  final Stopwatch _checkpointStopwatch;

  void checkpoint(String description) {
    final checkpointMilliseconds = _checkpointStopwatch.elapsedMilliseconds;
    final totalMilliseconds = _totalStopwatch.elapsedMilliseconds;

    debugPrint(
      '[$operationName] $description: '
      '${checkpointMilliseconds} ms '
      '(total: ${totalMilliseconds} ms)',
    );

    _checkpointStopwatch
      ..reset()
      ..start();
  }

  void finish([String description = 'COMPLETED']) {
    _checkpointStopwatch.stop();
    _totalStopwatch.stop();

    debugPrint(
      '[$operationName] $description — '
      'TOTAL: ${_totalStopwatch.elapsedMilliseconds} ms',
    );
  }

  void fail(Object error) {
    _checkpointStopwatch.stop();
    _totalStopwatch.stop();

    debugPrint(
      '[$operationName] FAILED after '
      '${_totalStopwatch.elapsedMilliseconds} ms: $error',
    );
  }
}
