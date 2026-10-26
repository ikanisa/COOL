import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';

import 'payment_help_storage_contract.dart';

class _NativePaymentHelpStorage implements PaymentHelpProtectedStorage {
  static const _channel = MethodChannel('collect/payment_help_pending');
  static final _queue = Queue<void Function()>();
  static bool _running = false;

  @override
  Future<T> exclusive<T>(Future<T> Function() action) {
    final result = Completer<T>(), zone = Zone.current;
    _queue.add(
      () => zone.run(() async {
        try {
          final value = await action();
          _running = false;
          result.complete(value);
        } catch (error, stack) {
          _running = false;
          result.completeError(error, stack);
        } finally {
          _drain();
        }
      }),
    );
    _drain();
    return result.future;
  }

  static void _drain() {
    if (_running || _queue.isEmpty) return;
    _running = true;
    _queue.removeFirst()();
  }

  @override
  Future<String?> read(String ownerId) async {
    try {
      return await _channel.invokeMethod<String>('read', {'owner_id': ownerId});
    } on MissingPluginException {
      throw StateError('Protected payment-help recovery is unavailable.');
    }
  }

  @override
  Future<void> write(String ownerId, String value) async {
    try {
      if (await _channel.invokeMethod<bool>('write', {
            'owner_id': ownerId,
            'value': value,
          }) !=
          true) {
        throw StateError('Payment help could not be saved. Try again.');
      }
    } on MissingPluginException {
      throw StateError('Protected payment-help recovery is unavailable.');
    }
  }

  @override
  Future<void> clear(String ownerId) async {
    try {
      if (await _channel.invokeMethod<bool>('clear', {'owner_id': ownerId}) !=
          true) {
        throw StateError('Saved payment help could not be cleared.');
      }
    } on MissingPluginException {
      // A host with no bridge cannot have saved a request through this adapter.
    }
  }
}

PaymentHelpProtectedStorage createStore() => _NativePaymentHelpStorage();
