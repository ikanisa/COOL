import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'admin_privacy_review_checkpoint.dart';
import 'admin_privacy_review_models.dart';

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

class _Store extends AdminPrivacyReviewJournalStore {
  _Store()
    : super(
        readRaw: (key) => web.window.localStorage.getItem(key),
        writeRaw: (key, value) => web.window.localStorage.setItem(key, value),
        exclusive: _exclusive,
      );
  static Future<void> _exclusive(String owner, void Function() work) async {
    const bound = Duration(seconds: 5);
    final manager = _locks;
    if (manager == null) privacyReviewInvalid();
    final abort = _AbortController(), elapsed = Stopwatch()..start();
    var closed = false, ran = false;
    Object? failure;
    StackTrace? stack;
    void close() {
      closed = true;
      abort.abort();
    }

    final timer = Timer(bound, close);
    try {
      await manager
          .request(
            '$owner.exclusive',
            _LockOptions(mode: 'exclusive', signal: abort.signal),
            ((JSAny? lock) {
              ran = true;
              try {
                if (closed || elapsed.elapsed >= bound || lock == null) {
                  privacyReviewInvalid();
                }
                work();
              } catch (e, s) {
                failure = e;
                stack = s;
              }
              return null;
            }).toJS,
          )
          .toDart
          .timeout(
            bound,
            onTimeout: () {
              close();
              privacyReviewInvalid();
            },
          );
      if (closed || !ran) privacyReviewInvalid();
      if (failure != null) Error.throwWithStackTrace(failure!, stack!);
    } finally {
      timer.cancel();
      close();
    }
  }
}

AdminPrivacyReviewStore createStore() => _Store();
