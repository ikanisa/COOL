import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'admin_full_payment_compensation_models.dart';
import 'admin_full_payment_compensation_checkpoint.dart';

@JS('navigator.locks')
external _Locks? get _locks;
extension type _Locks(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(
    String name,
    _LockOptions options,
    JSFunction callback,
  );
}

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

extension type _LockOptions._(JSObject _) implements JSObject {
  external factory _LockOptions({String mode, JSObject signal});
}

class _Store extends AdminFullPaymentCompensationJournalStore {
  _Store()
    : super(
        readRaw: (key) => web.window.localStorage.getItem(key),
        writeRaw: (key, value) => web.window.localStorage.setItem(key, value),
        exclusive: _exclusive,
      );
  static const _lockBound = Duration(seconds: 5);
  static Future<void> _exclusive(String owner, void Function() work) async {
    final manager = _locks;
    if (manager == null) compensationInvalid();
    final abort = _AbortController(), elapsed = Stopwatch()..start();
    var closed = false, ran = false;
    Object? failure;
    StackTrace? failureStack;
    void close() {
      closed = true;
      abort.abort();
    }

    final timer = Timer(_lockBound, close);
    try {
      await manager
          .request(
            '$owner.exclusive',
            _LockOptions(mode: 'exclusive', signal: abort.signal),
            ((JSAny? lock) {
              // Preserve typed Dart refusal across JS promise callbacks.
              ran = true;
              try {
                if (closed || elapsed.elapsed >= _lockBound || lock == null) {
                  compensationInvalid();
                }
                work();
              } catch (error, stack) {
                failure = error;
                failureStack = stack;
              }
              return null;
            }).toJS,
          )
          .toDart
          .timeout(
            _lockBound,
            onTimeout: () {
              close();
              compensationInvalid();
            },
          );
      if (closed || !ran) compensationInvalid();
      if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    } finally {
      timer.cancel();
      close();
    }
  }
}

AdminFullPaymentCompensationStore createStore() => _Store();
