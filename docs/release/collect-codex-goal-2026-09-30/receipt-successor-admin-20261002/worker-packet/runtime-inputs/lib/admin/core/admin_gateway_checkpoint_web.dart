import 'dart:js_interop';
import 'admin_gateway_checkpoint.dart';

@JS('window.sessionStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

class _BrowserStore implements AdminGatewayCheckpointStore {
  String _key(String digest) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid recovery binding.');
    }
    return 'collect.admin.gateway.recovery.v1.$digest';
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
