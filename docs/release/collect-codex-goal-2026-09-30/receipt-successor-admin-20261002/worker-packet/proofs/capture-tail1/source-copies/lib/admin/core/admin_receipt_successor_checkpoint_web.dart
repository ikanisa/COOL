import 'dart:js_interop';
import 'admin_receipt_successor_checkpoint.dart';

@JS('window.sessionStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

class _BrowserStore implements AdminReceiptSuccessorCheckpointStore {
  String _key(String digest) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid receipt recovery binding.');
    }
    return 'collect.admin.receipt-successor.recovery.v1.$digest';
  }

  @override
  String? read(String digest) => _storage.getItem(_key(digest));
  @override
  void write(String digest, String encoded) =>
      _storage.setItem(_key(digest), encoded);
  @override
  void clear(String digest) => _storage.removeItem(_key(digest));
}

AdminReceiptSuccessorCheckpointStore createReceiptSuccessorCheckpointStore() =>
    _BrowserStore();
