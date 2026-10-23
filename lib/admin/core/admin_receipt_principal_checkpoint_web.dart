import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'admin_recovery_namespace.dart';

import 'admin_receipt_operations_models.dart';
import 'admin_receipt_principal_checkpoint.dart';

@JS('window.localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
}

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

class _BrowserPrincipalStore implements AdminReceiptPrincipalCheckpointStore {
  void _verifyNamespace() {
    verifyAdminRecoveryNamespace(
      retiredPrefix: 'collect.admin.receipt-principal.recovery.v3.',
      storageLength: () => _storage.length,
      keyAt: (index) => _storage.key(index),
    );
  }

  static const _lockBound = Duration(seconds: 5);
  String _prefix(String owner) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(owner)) operationsInvalid();
    return 'collect.admin.receipt-principal.recovery.v4.$owner.';
  }

  String _key(String owner, String request) =>
      '${_prefix(owner)}${operationsUuid(request)}';

  Future<T> _exclusive<T>(String owner, T Function() work) async {
    _verifyNamespace();
    final manager = _locks;
    if (manager == null) operationsInvalid();
    final abort = _AbortController(), elapsed = Stopwatch()..start();
    var closed = false, ran = false;
    late T result;
    void close() {
      closed = true;
      abort.abort();
    }

    final timer = Timer(_lockBound, close);
    try {
      await manager
          .request(
            '${_prefix(owner)}exclusive',
            _LockOptions(mode: 'exclusive', signal: abort.signal),
            ((JSAny? lock) {
              // Abort cancels queued acquisition. This sticky and monotonic
              // check also prevents late writes after throttled timers.
              if (closed || elapsed.elapsed >= _lockBound || lock == null) {
                operationsInvalid();
              }
              _verifyNamespace();
              result = work();
              ran = true;
              return null;
            }).toJS,
          )
          .toDart
          .timeout(
            _lockBound,
            onTimeout: () {
              close();
              operationsInvalid();
            },
          );
      if (closed || !ran) operationsInvalid();
      return result;
    } finally {
      timer.cancel();
      close();
    }
  }

  List<AdminReceiptPrincipalCheckpoint> _pending(String owner) {
    final prefix = _prefix(owner), originals = <String>{}, markers = <String>{};
    final length = _storage.length;
    if (length > 10000) operationsInvalid();
    for (var i = 0; i < length; i++) {
      final key = _storage.key(i);
      if (key == null || !key.startsWith(prefix)) continue;
      final suffix = key.substring(prefix.length);
      if (suffix.endsWith('.resolution')) {
        operationsUuid(suffix.substring(0, suffix.length - 11));
        markers.add(key.substring(0, key.length - 11));
      } else {
        operationsUuid(suffix);
        originals.add(key);
      }
    }
    if (originals.length > adminReceiptPrincipalMaximumOriginals ||
        !originals.containsAll(markers)) {
      operationsInvalid();
    }
    final pending = <AdminReceiptPrincipalCheckpoint>[];
    for (final key in originals) {
      final encoded = _storage.getItem(key);
      if (encoded == null) operationsInvalid();
      final original = AdminReceiptPrincipalCheckpoint.parse(encoded, owner);
      if (key != _key(owner, original.requestId)) operationsInvalid();
      final resolution = _storage.getItem('$key.resolution');
      if (resolution == null) {
        pending.add(original);
      } else {
        if (resolution.length > 512) operationsInvalid();
        final marker = operationsObject(jsonDecode(resolution), {
          'version',
          'owner_digest',
          'request_id',
          'original_sha256',
          'status',
        });
        if (marker['version'] is! int ||
            marker['version'] != 3 ||
            marker['owner_digest'] != owner ||
            marker['request_id'] != original.requestId ||
            marker['original_sha256'] != original.digest ||
            !{
              'recorded',
              'not_recorded_after_deadline',
            }.contains(marker['status']) ||
            jsonEncode(marker) != resolution) {
          operationsInvalid();
        }
      }
      if (_storage.getItem(key) != encoded ||
          _storage.getItem('$key.resolution') != resolution) {
        operationsInvalid();
      }
    }
    if (_storage.length != length ||
        pending.length > adminReceiptPrincipalMaximumPending) {
      operationsInvalid();
    }
    pending.sort((a, b) => a.binding.createdAt.compareTo(b.binding.createdAt));
    return pending;
  }

  @override
  Future<List<String>> read(String ownerDigest) => _exclusive(
    ownerDigest,
    () => _pending(ownerDigest).map((p) => p.encode()).toList(),
  );

  @override
  Future<void> write(
    String ownerDigest,
    String requestId,
    String encoded, {
    required bool Function() isCurrent,
  }) => _exclusive(ownerDigest, () {
    if (!isCurrent()) operationsInvalid();
    final original = AdminReceiptPrincipalCheckpoint.parse(
      encoded,
      ownerDigest,
    );
    final pending = _pending(ownerDigest), key = _key(ownerDigest, requestId);
    if (original.requestId != requestId ||
        _storage.getItem(key) != null ||
        _storage.getItem('$key.resolution') != null ||
        !adminReceiptPrincipalMayPublish(pending, original.binding)) {
      operationsInvalid();
    }
    // Include resolved originals in the immutable retention bound.
    var count = 0;
    for (var i = 0; i < _storage.length; i++) {
      final name = _storage.key(i);
      if (name != null &&
          name.startsWith(_prefix(ownerDigest)) &&
          !name.endsWith('.resolution')) {
        count++;
      }
    }
    if (count >= adminReceiptPrincipalMaximumOriginals) operationsInvalid();
    _storage.setItem(key, encoded);
    if (_storage.getItem(key) != encoded) operationsInvalid();
  });

  @override
  Future<void> resolve(
    AdminReceiptPrincipalCheckpoint checkpoint,
    String status, {
    required bool Function() isCurrent,
  }) => _exclusive(checkpoint.ownerDigest, () {
    if (!isCurrent()) operationsInvalid();
    if (!{'recorded', 'not_recorded_after_deadline'}.contains(status)) {
      operationsInvalid();
    }
    _pending(checkpoint.ownerDigest);
    final key = _key(checkpoint.ownerDigest, checkpoint.requestId);
    if (_storage.getItem(key) != checkpoint.encode()) operationsInvalid();
    final marker = jsonEncode({
      'version': 3,
      'owner_digest': checkpoint.ownerDigest,
      'request_id': checkpoint.requestId,
      'original_sha256': checkpoint.digest,
      'status': status,
    });
    final previous = _storage.getItem('$key.resolution');
    if (previous != null && previous != marker) operationsInvalid();
    _storage.setItem('$key.resolution', marker);
    if (_storage.getItem('$key.resolution') != marker ||
        _storage.getItem(key) != checkpoint.encode()) {
      operationsInvalid();
    }
  });
}

AdminReceiptPrincipalCheckpointStore createReceiptPrincipalCheckpointStore() =>
    _BrowserPrincipalStore();
