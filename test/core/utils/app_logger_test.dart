import 'package:cool_app/core/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogger', () {
    const logger = AppLogger('TestTag');

    test('debug logs with tag and bug emoji in debug mode', () {
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      logger.debug('test debug message');

      expect(logs, hasLength(1));
      expect(logs.first, contains('[TestTag]'));
      expect(logs.first, contains('🐛'));
      expect(logs.first, contains('test debug message'));

      // Restore default.
      debugPrint = debugPrintThrottled;
    });

    test('info logs with tag and info emoji in debug mode', () {
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      logger.info('test info message');

      expect(logs, hasLength(1));
      expect(logs.first, contains('[TestTag]'));
      expect(logs.first, contains('ℹ️'));
      expect(logs.first, contains('test info message'));

      debugPrint = debugPrintThrottled;
    });

    test('warn logs with tag and warning emoji in debug mode', () {
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      logger.warn('something sketchy', error: Exception('badness'));

      expect(logs, hasLength(1));
      expect(logs.first, contains('[TestTag]'));
      expect(logs.first, contains('⚠️'));
      expect(logs.first, contains('something sketchy'));
      expect(logs.first, contains('badness'));

      debugPrint = debugPrintThrottled;
    });

    test('error logs with tag and error emoji in debug mode', () {
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      logger.error(
        'critical failure',
        error: StateError('boom'),
        stack: StackTrace.current,
      );

      expect(logs.length, greaterThanOrEqualTo(1));
      expect(logs.first, contains('[TestTag]'));
      expect(logs.first, contains('❌'));
      expect(logs.first, contains('critical failure'));

      debugPrint = debugPrintThrottled;
    });

    test('different tags create separate loggers', () {
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };

      const loggerA = AppLogger('ServiceA');
      const loggerB = AppLogger('ServiceB');

      loggerA.info('message A');
      loggerB.info('message B');

      expect(logs[0], contains('[ServiceA]'));
      expect(logs[1], contains('[ServiceB]'));

      debugPrint = debugPrintThrottled;
    });
  });
}
