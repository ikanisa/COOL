import 'dart:async';

import 'package:cool_app/core/sync/network_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNetworkError', () {
    test('TimeoutException is a network error', () {
      expect(isNetworkError(TimeoutException('timeout')), isTrue);
    });

    test('SocketException message is a network error', () {
      expect(
        isNetworkError(Exception('SocketException: OS Error')),
        isTrue,
      );
    });

    test('Failed host lookup is a network error', () {
      expect(
        isNetworkError(Exception('Failed host lookup: example.com')),
        isTrue,
      );
    });

    test('Connection refused is a network error', () {
      expect(
        isNetworkError(Exception('Connection refused')),
        isTrue,
      );
    });

    test('Connection reset is a network error', () {
      expect(
        isNetworkError(Exception('Connection reset by peer')),
        isTrue,
      );
    });

    test('Timed out is a network error', () {
      expect(
        isNetworkError(Exception('Request timed out')),
        isTrue,
      );
    });

    test('XMLHttpRequest error is a network error', () {
      expect(
        isNetworkError(Exception('XMLHttpRequest error')),
        isTrue,
      );
    });

    test('ClientException is a network error', () {
      expect(
        isNetworkError(Exception('ClientException: Connection closed')),
        isTrue,
      );
    });

    test('Generic Exception is NOT a network error', () {
      expect(
        isNetworkError(Exception('Something went wrong')),
        isFalse,
      );
    });

    test('StateError is NOT a network error', () {
      expect(isNetworkError(StateError('bad state')), isFalse);
    });

    test('FormatException is NOT a network error', () {
      expect(isNetworkError(const FormatException('bad format')), isFalse);
    });
  });
}
