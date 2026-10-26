import 'dart:convert';
import 'dart:js_interop';
import 'admin_recovery_namespace.dart';
import 'admin_receipt_operations_checkpoint.dart';
import 'admin_receipt_operations_models.dart';

@JS('window.localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
}

class _BrowserStore implements AdminReceiptOperationsCheckpointStore {
  void _verifyNamespace() {
    verifyAdminRecoveryNamespace(
      retiredPrefix: 'collect.admin.receipt-operations.recovery.v2.',
      storageLength: () => _storage.length,
      keyAt: (index) => _storage.key(index),
    );
  }

  String _prefix(String owner) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(owner)) operationsInvalid();
    return 'collect.admin.receipt-operations.recovery.v3.$owner.';
  }

  String _key(String owner, String requestId) =>
      '${_prefix(owner)}${operationsUuid(requestId)}';
  @override
  List<String> read(String ownerDigest) {
    _verifyNamespace();
    final prefix = _prefix(ownerDigest), result = <String>[];
    final keys = <String>[];
    final length = _storage.length;
    if (length > 10000) operationsInvalid();
    for (var i = 0; i < length; i++) {
      final key = _storage.key(i);
      if (key != null &&
          key.startsWith(prefix) &&
          !key.endsWith('.resolution')) {
        keys.add(key);
      }
    }
    if (keys.length > 500) operationsInvalid();
    for (final key in keys) {
      final encoded = _storage.getItem(key);
      if (encoded == null) operationsInvalid();
      final checkpoint = AdminReceiptOperationsCheckpoint.parse(
        encoded,
        ownerDigest,
      );
      if (key != _key(ownerDigest, checkpoint.requestId)) operationsInvalid();
      final resolved = _storage.getItem('$key.resolution');
      if (resolved == null) {
        result.add(encoded);
      } else {
        if (resolved.length > 1024) operationsInvalid();
        final marker = operationsObject(jsonDecode(resolved), {
          'version',
          'original_sha256',
          'status',
        });
        if (marker['version'] is! int ||
            marker['version'] != 2 ||
            marker['original_sha256'] != checkpoint.digest ||
            marker['status'] is! String ||
            !{
              'recorded',
              'not_recorded_after_deadline',
            }.contains(marker['status'])) {
          operationsInvalid();
        }
      }
    }
    return result;
  }

  @override
  void write(String ownerDigest, String requestId, String encoded) {
    _verifyNamespace();
    final checkpoint = AdminReceiptOperationsCheckpoint.parse(
      encoded,
      ownerDigest,
    );
    if (checkpoint.requestId != requestId) operationsInvalid();
    final key = _key(ownerDigest, requestId);
    if (_storage.getItem(key) != null) operationsInvalid();
    _storage.setItem(key, encoded);
    if (_storage.getItem(key) != encoded) operationsInvalid();
  }

  @override
  void resolve(AdminReceiptOperationsCheckpoint checkpoint, String status) {
    _verifyNamespace();
    if (!{'recorded', 'not_recorded_after_deadline'}.contains(status)) {
      operationsInvalid();
    }
    final key = _key(checkpoint.ownerDigest, checkpoint.requestId);
    if (_storage.getItem(key) != checkpoint.encode()) operationsInvalid();
    final marker = jsonEncode({
      'version': 2,
      'original_sha256': checkpoint.digest,
      'status': status,
    });
    final previous = _storage.getItem('$key.resolution');
    if (previous != null && previous != marker) operationsInvalid();
    _storage.setItem('$key.resolution', marker);
    if (_storage.getItem('$key.resolution') != marker) operationsInvalid();
  }
}

AdminReceiptOperationsCheckpointStore
createReceiptOperationsCheckpointStore() => _BrowserStore();
