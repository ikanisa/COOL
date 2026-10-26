import 'dart:js_interop';
import 'admin_recovery_namespace.dart';
import 'admin_gateway_checkpoint.dart';

@JS('window.sessionStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

class _BrowserStore implements AdminGatewayCheckpointStore {
  String _key(String digest) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid recovery binding.');
    }
    verifyAdminRecoveryNamespace(
      retiredPrefix: 'collect.admin.gateway.recovery.v1.',
      storageLength: () => _storage.length,
      keyAt: (index) => _storage.key(index),
    );
    return 'collect.admin.gateway.recovery.v2.$digest';
  }

  @override
  String? read(String ownerDigest) => _storage.getItem(_key(ownerDigest));
  @override
  void write(String ownerDigest, String encoded) =>
      _storage.setItem(_key(ownerDigest), encoded);
  @override
  void clear(String ownerDigest) => _storage.removeItem(_key(ownerDigest));
}

AdminGatewayCheckpointStore createGatewayCheckpointStore() => _BrowserStore();
