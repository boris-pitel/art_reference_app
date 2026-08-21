import 'package:art_reference_app/services/user_activity_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final logger = UserActivityLogger.instance;
  late List<Map<String, Object?>> entries;

  setUp(() {
    entries = [];
    // Capture instead of inserting, so these exercise the real trace/log path
    // rather than a copy of it.
    logger.sink = (entry) async => entries.add(entry);
  });

  tearDown(() => logger.sink = null);

  List<Object?> statuses() => entries.map((e) => e['status']).toList();

  group('trace', () {
    test('records started before the work and succeeded after', () async {
      final order = <String>[];

      logger.sink = (entry) async {
        entries.add(entry);
        order.add('logged ${entry['status']}');
      };

      await logger.trace(
        operation: 'image_save',
        action: () async {
          order.add('work ran');
          return 'ok';
        },
      );

      await _settle();

      expect(order, ['logged started', 'work ran', 'logged succeeded']);
    });

    test('records failed and lets the error through', () async {
      await expectLater(
        logger.trace<void>(
          operation: 'image_save',
          action: () async => throw StateError('the download timed out'),
        ),
        throwsStateError,
      );

      await _settle();

      // Re-throwing matters: the existing handling still has to run so the
      // user is told. Logging the failure must not swallow it.
      expect(statuses(), ['started', 'failed']);
      expect(entries.last['error_message'], contains('timed out'));
    });

    test('a cancelled action is neither a success nor a failure', () async {
      await logger.trace(
        operation: 'image_save',
        action: () async => 'cancelled',
        outcome: (result) => result == 'cancelled' ? 'cancelled' : 'succeeded',
      );

      await _settle();

      expect(statuses(), ['started', 'cancelled']);
    });

    test('records how long the work took', () async {
      await logger.trace(
        operation: 'image_save',
        action: () async =>
            Future<void>.delayed(const Duration(milliseconds: 20)),
      );

      await _settle();

      expect(entries.last['duration_ms'], greaterThanOrEqualTo(15));
    });

    test('a started with no end is what a silent failure looks like', () async {
      // An action that never completes: the platform accepted the work and
      // said nothing back. This is the case the design exists for — the row
      // present without its partner is the evidence.
      unawaited(
        logger.trace<void>(
          operation: 'image_save',
          action: () => Future<void>.delayed(const Duration(days: 1)),
        ),
      );

      await _settle();

      expect(statuses(), ['started']);
    });

    test('carries the target through to both entries', () async {
      await logger.trace(
        operation: 'image_save',
        targetType: 'image',
        targetId: 'abc-123',
        action: () async {},
      );

      await _settle();

      expect(entries.every((e) => e['target_id'] == 'abc-123'), isTrue);
    });
  });

  group('sessionId', () {
    test('stays the same across calls in one sitting', () {
      expect(logger.sessionId, logger.sessionId);
    });

    test('is a usable identifier', () {
      expect(logger.sessionId, isNotEmpty);
    });
  });
}

/// `record` fires the insert without awaiting it, so the sink runs a
/// microtask later than the call that triggered it.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void unawaited(Future<void> future) {
  future.catchError((_) {});
}
