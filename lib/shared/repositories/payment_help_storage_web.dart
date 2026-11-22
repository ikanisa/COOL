import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'payment_help_storage_contract.dart';

PaymentHelpProtectedStorage createStore() => WebPaymentHelpProtectedStorage();

/// Payment Help has its own encrypted browser namespace. The browser persists a
/// nonextractable CryptoKey by structured clone; no exported key or plaintext
/// fallback is written to another browser store.
final class WebPaymentHelpProtectedStorage
    implements PaymentHelpProtectedStorage {
  static const _databaseName = 'collect.payment_help.v1';
  static const _storeName = 'records';
  static const _lockName = 'collect.payment_help.v1.transaction';
  static const _maxBytes = 1024 * 1024;
  static final _lockZoneKey = Object();
  static final _ownerPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  @override
  Future<T> exclusive<T>(Future<T> Function() action) async {
    final inheritedLease = Zone.current[_lockZoneKey];
    if (inheritedLease is _LockLease && inheritedLease.active) return action();
    late T result;
    Object? actionError;
    StackTrace? actionStack;
    try {
      if (!web.window.isSecureContext) throw StateError('Insecure context');
      await web.window.navigator.locks
          .request(
            _lockName,
            ((web.Lock lock) {
              return (() async {
                final lease = _LockLease();
                try {
                  result = await runZoned(
                    action,
                    zoneValues: {_lockZoneKey: lease},
                  );
                } catch (error, stack) {
                  actionError = error;
                  actionStack = stack;
                } finally {
                  // A delayed callback retaining this Zone cannot reuse a
                  // browser lock after the request callback has released it.
                  lease.active = false;
                }
                return null;
              })().toJS;
            }).toJS,
          )
          .toDart;
    } catch (_) {
      throw StateError('Protected Payment Help recovery is unavailable.');
    }
    if (actionError != null) {
      Error.throwWithStackTrace(actionError!, actionStack!);
    }
    return result;
  }

  @override
  Future<String?> read(String ownerId) => exclusive(() async {
    final owner = _owner(ownerId);
    final database = await _open();
    try {
      final raw = await _readRecord(database, await _recordKey(owner));
      if (raw == null) return null;
      return _decrypt(owner, _validatedRecord(raw));
    } finally {
      database.close();
    }
  });

  @override
  Future<void> write(String ownerId, String value) => exclusive(() async {
    final owner = _owner(ownerId);
    final bytes = Uint8List.fromList(utf8.encode(value));
    if (bytes.length > _maxBytes) {
      throw StateError('Payment Help recovery exceeds its protected limit.');
    }
    final database = await _open();
    try {
      final recordKey = await _recordKey(owner);
      final existing = await _readRecord(database, recordKey);
      final web.CryptoKey key;
      if (existing == null) {
        key =
            (await web.window.crypto.subtle
                    .generateKey(
                      _KeyAlgorithm(name: 'AES-GCM', length: 256),
                      false,
                      ['encrypt'.toJS, 'decrypt'.toJS].toJS,
                    )
                    .toDart)
                as web.CryptoKey;
      } else {
        final record = _validatedRecord(existing);
        // Never replace unreadable recovery evidence with a fresh request.
        await _decrypt(owner, record);
        key = record.key;
      }
      final nonce = Uint8List(12);
      web.window.crypto.getRandomValues(nonce.toJS);
      final encrypted =
          (await web.window.crypto.subtle
                  .encrypt(_parameters(owner, nonce), key, bytes.toJS)
                  .toDart)
              as JSArrayBuffer;
      final record = _EncryptedRecord(
        version: 1,
        key: key,
        nonce: nonce.toJS,
        ciphertext: encrypted,
      );
      await _transaction(
        database,
        'readwrite',
        (store) => store.put(record, recordKey.toJS),
      );
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('Protected Payment Help recovery could not be saved.');
    } finally {
      database.close();
    }
  });

  @override
  Future<void> clear(String ownerId) => exclusive(() async {
    final owner = _owner(ownerId);
    final database = await _open();
    try {
      final key = await _recordKey(owner);
      await _transaction(
        database,
        'readwrite',
        (store) => store.delete(key.toJS),
      );
    } finally {
      database.close();
    }
  });

  String _owner(String value) {
    final owner = value.toLowerCase();
    if (!_ownerPattern.hasMatch(owner)) {
      throw ArgumentError.value(null, 'ownerId', 'A valid owner is required.');
    }
    return owner;
  }

  Future<String> _recordKey(String owner) async {
    try {
      final digest =
          (await web.window.crypto.subtle
                  .digest('SHA-256'.toJS, _aad(owner).toJS)
                  .toDart)
              as JSArrayBuffer;
      return digest.toDart.asUint8List().map((b) {
        return b.toRadixString(16).padLeft(2, '0');
      }).join();
    } catch (_) {
      throw StateError('Protected Payment Help recovery is unavailable.');
    }
  }

  Uint8List _aad(String owner) =>
      Uint8List.fromList(utf8.encode('collect.payment_help.v1:$owner'));

  _CipherAlgorithm _parameters(String owner, Uint8List nonce) =>
      _CipherAlgorithm(
        name: 'AES-GCM',
        iv: nonce.toJS,
        additionalData: _aad(owner).toJS,
        tagLength: 128,
      );

  _EncryptedRecord _validatedRecord(JSAny raw) {
    try {
      final record = raw as _EncryptedRecord;
      final algorithm = record.key.algorithm as _KeyAlgorithm;
      final usages = (record.key.usages as JSArray<JSString>).toDart.map(
        (value) => value.toDart,
      );
      if (record.version != 1 ||
          record.key.type != 'secret' ||
          record.key.extractable ||
          algorithm.name != 'AES-GCM' ||
          algorithm.length != 256 ||
          usages.length != 2 ||
          !usages.contains('encrypt') ||
          !usages.contains('decrypt') ||
          record.nonce.toDart.length != 12 ||
          record.ciphertext.toDart.lengthInBytes < 16 ||
          record.ciphertext.toDart.lengthInBytes > _maxBytes + 16) {
        throw StateError('Invalid recovery');
      }
      return record;
    } catch (_) {
      throw StateError('Protected Payment Help recovery is unreadable.');
    }
  }

  Future<String> _decrypt(String owner, _EncryptedRecord record) async {
    try {
      final decrypted =
          (await web.window.crypto.subtle
                  .decrypt(
                    _parameters(owner, record.nonce.toDart),
                    record.key,
                    record.ciphertext,
                  )
                  .toDart)
              as JSArrayBuffer;
      final bytes = decrypted.toDart.asUint8List();
      if (bytes.length > _maxBytes) throw StateError('Invalid recovery');
      return utf8.decode(bytes);
    } catch (_) {
      // Preserve the record for explicit owner cleanup or recovery diagnosis.
      throw StateError('Protected Payment Help recovery is unreadable.');
    }
  }

  Future<web.IDBDatabase> _open() async {
    final result = Completer<web.IDBDatabase>();
    try {
      final request = web.window.indexedDB.open(_databaseName, 1);
      request.onupgradeneeded = ((web.Event event) {
        try {
          final database = request.result as web.IDBDatabase;
          if (!database.objectStoreNames.contains(_storeName)) {
            database.createObjectStore(_storeName);
          }
        } catch (_) {
          request.transaction?.abort();
          if (!result.isCompleted) {
            result.completeError(
              StateError('Protected Payment Help recovery is unavailable.'),
            );
          }
        }
      }).toJS;
      request.onsuccess = ((web.Event event) {
        final database = request.result as web.IDBDatabase;
        if (result.isCompleted) {
          database.close();
          return;
        }
        database.onversionchange = ((web.Event event) {
          database.close();
        }).toJS;
        result.complete(database);
      }).toJS;
      void fail(web.Event event) {
        if (!result.isCompleted) {
          result.completeError(
            StateError('Protected Payment Help recovery is unavailable.'),
          );
        }
      }

      request.onerror = fail.toJS;
      request.onblocked = fail.toJS;
    } catch (_) {
      throw StateError('Protected Payment Help recovery is unavailable.');
    }
    return result.future;
  }

  Future<JSAny?> _readRecord(web.IDBDatabase database, String key) =>
      _transaction(database, 'readonly', (store) => store.get(key.toJS));

  Future<JSAny?> _transaction(
    web.IDBDatabase database,
    String mode,
    web.IDBRequest Function(web.IDBObjectStore) requestAction,
  ) async {
    final result = Completer<JSAny?>();
    web.IDBTransaction? transaction;
    try {
      transaction = database.transaction(
        _storeName.toJS,
        mode,
        web.IDBTransactionOptions(durability: 'strict'),
      );
      JSAny? value;
      transaction.oncomplete = ((web.Event event) {
        if (!result.isCompleted) result.complete(value);
      }).toJS;
      void fail(web.Event event) {
        if (!result.isCompleted) {
          result.completeError(
            StateError('Protected Payment Help recovery did not commit.'),
          );
        }
      }

      transaction.onabort = fail.toJS;
      transaction.onerror = fail.toJS;
      final request = requestAction(transaction.objectStore(_storeName));
      request.onsuccess = ((web.Event event) {
        value = request.result;
      }).toJS;
      // A request success does not acknowledge a write: oncomplete above does.
    } catch (_) {
      try {
        transaction?.abort();
      } catch (_) {
        // No active transaction remains to roll back.
      }
      if (!result.isCompleted) {
        result.completeError(
          StateError('Protected Payment Help recovery is unavailable.'),
        );
      }
    }
    return result.future;
  }
}

final class _LockLease {
  bool active = true;
}

extension type _KeyAlgorithm._(JSObject _) implements JSObject {
  external factory _KeyAlgorithm({String name, int length});
  external String get name;
  external int get length;
}

extension type _CipherAlgorithm._(JSObject _) implements JSObject {
  external factory _CipherAlgorithm({
    String name,
    JSUint8Array iv,
    JSUint8Array additionalData,
    int tagLength,
  });
}

extension type _EncryptedRecord._(JSObject _) implements JSObject {
  external factory _EncryptedRecord({
    int version,
    web.CryptoKey key,
    JSUint8Array nonce,
    JSArrayBuffer ciphertext,
  });
  external int get version;
  external web.CryptoKey get key;
  external JSUint8Array get nonce;
  external JSArrayBuffer get ciphertext;
}
