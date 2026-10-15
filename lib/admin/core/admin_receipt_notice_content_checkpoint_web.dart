import 'dart:convert';
import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'admin_receipt_notice_content_models.dart';
import 'admin_receipt_notice_content_checkpoint.dart';

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

class _Store implements AdminReceiptNoticeContentStore {
  static const _lockBound = Duration(seconds: 5);
  Future<T> _exclusive<T>(String owner, T Function() work) async {
    final manager = _locks;
    if (manager == null) noticeInvalid();
    final abort = _AbortController(), elapsed = Stopwatch()..start();
    var closed = false, ran = false;
    late T result;
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
            '${'collect.notice-content.v1.$owner.'}exclusive',
            _LockOptions(mode: 'exclusive', signal: abort.signal),
            ((JSAny? lock) {
              // Preserve typed Dart refusal across JS promise callbacks.
              ran = true;
              try {
                if (closed || elapsed.elapsed >= _lockBound || lock == null) {
                  noticeInvalid();
                }
                result = work();
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
              noticeInvalid();
            },
          );
      if (closed || !ran) noticeInvalid();
      if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
      return result;
    } finally {
      timer.cancel();
      close();
    }
  }

  String _key(String actor, String session) =>
      'collect.notice-content.v1.${noticeUuid(actor)}.${noticeUuid(session)}';
  AdminReceiptNoticeIntent? _read(String actor, String session) {
    final raw = web.window.localStorage.getItem(_key(actor, session));
    if (raw == null) return null;
    if (raw.length > 32768) noticeInvalid();
    final i = AdminReceiptNoticeIntent.parse(jsonDecode(raw));
    if (i.actorId != actor || i.sessionId != session) noticeInvalid();
    return i;
  }

  @override
  Future<AdminReceiptNoticeIntent?> read(String actor, String session) async =>
      _read(actor, session);
  @override
  Future<void> write(
    AdminReceiptNoticeIntent intent,
  ) => _exclusive('${intent.actorId}.${intent.sessionId}', () {
    final resolved = web.window.localStorage.getItem(
      '${_key(intent.actorId, intent.sessionId)}.resolved.${intent.requestId}',
    );
    if (resolved != null) {
      noticeInvalid();
    }
    final old = _read(intent.actorId, intent.sessionId);
    if (old != null && old.fingerprint != intent.fingerprint) {
      noticeInvalid();
    }
    web.window.localStorage.setItem(
      _key(intent.actorId, intent.sessionId),
      jsonEncode(intent.row),
    );
    if (_read(intent.actorId, intent.sessionId)?.fingerprint !=
        intent.fingerprint) {
      noticeInvalid();
    }
  });
  @override
  Future<void> clear(
    AdminReceiptNoticeIntent intent,
  ) => _exclusive('${intent.actorId}.${intent.sessionId}', () {
    if (_read(intent.actorId, intent.sessionId)?.fingerprint !=
        intent.fingerprint) {
      noticeInvalid();
    }
    final retainedKey =
        '${_key(intent.actorId, intent.sessionId)}.resolved.${intent.requestId}';
    final raw = jsonEncode(intent.row),
        old = web.window.localStorage.getItem(retainedKey);
    if (old != null && old != raw) noticeInvalid();
    web.window.localStorage.setItem(retainedKey, raw);
    if (web.window.localStorage.getItem(retainedKey) != raw) noticeInvalid();
    web.window.localStorage.removeItem(_key(intent.actorId, intent.sessionId));
    if (_read(intent.actorId, intent.sessionId) != null) noticeInvalid();
  });
}

AdminReceiptNoticeContentStore createStore() => _Store();
