import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../data/exact_json_values.dart';
import '../payments/contribution_command.dart';
import 'contribution_command_storage_contract.dart';

ContributionCommandProtectedStorage createStore() =>
    WebContributionCommandStorage();

/// Independent encrypted namespace. Every admitted tab/worker uses the same
/// Web Lock. A strict IDB transaction completion acknowledges a winning CAS.
final class WebContributionCommandStorage
    implements ContributionCommandProtectedStorage {
  static const _databaseName = 'collect.contribution_commands.v1';
  static const _storeName = 'records';
  static const _lockName = 'collect.contribution_commands.v1.transaction';
  static const _maxPartitions = 64, _maxAggregateBytes = 16777216;

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    late T result;
    Object? error;
    StackTrace? stack;
    if (!web.window.isSecureContext) {
      throw StateError('Protected contribution recovery is unavailable.');
    }
    try {
      await web.window.navigator.locks
          .request(
            _lockName,
            web.LockOptions(mode: 'exclusive', ifAvailable: true),
            ((web.Lock? lock) {
              return (() async {
                try {
                  if (lock == null) {
                    throw StateError(
                      'Contribution recovery is busy. Check the original request.',
                    );
                  }
                  result = await action();
                } catch (e, s) {
                  error = e;
                  stack = s;
                }
                return null;
              })().toJS;
            }).toJS,
          )
          .toDart;
    } catch (_) {
      throw StateError('Protected contribution recovery is unavailable.');
    }
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return result;
  }

  String _partition(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException('Invalid recovery partition.');
    }
    return value;
  }

  @override
  Future<ContributionStoreSnapshot> read(String partitionId) =>
      _exclusive(() async {
        final partition = _partition(partitionId), db = await _open();
        try {
          final raw = await _transaction(
            db,
            'readonly',
            (s) => s.get(partition.toJS),
          );
          if (raw == null) {
            return ContributionStoreSnapshot(
              partitionId: partition,
              revision: 0,
              payload: null,
            );
          }
          return _decrypt(partition, _validated(raw));
        } finally {
          db.close();
        }
      });

  @override
  Future<ContributionStoreCasResult> compareAndSet(
    String partitionId,
    int expectedRevision,
    String payload,
  ) => _exclusive(() async {
    final partition = _partition(partitionId);
    exactJsonInteger(
      expectedRevision,
      field: 'contribution.store_revision',
      minimum: 0,
      maximum: maxExactJsonInteger - 1,
    );
    final bytes = Uint8List.fromList(utf8.encode(payload));
    if (bytes.isEmpty ||
        bytes.length > contributionCommandMaxPayloadBytes ||
        utf8.decode(bytes) != payload) {
      throw StateError('Contribution recovery exceeds its protected limit.');
    }
    final db = await _open();
    try {
      final raw = await _transaction(
        db,
        'readonly',
        (s) => s.get(partition.toJS),
      );
      final previous = raw == null ? null : _validated(raw);
      final snapshot = previous == null
          ? ContributionStoreSnapshot(
              partitionId: partition,
              revision: 0,
              payload: null,
            )
          : await _decrypt(partition, previous);
      if (snapshot.revision != expectedRevision) {
        return ContributionStoreCasResult(committed: false, snapshot: snapshot);
      }
      final all = await _transaction(db, 'readonly', (s) => s.getAll());
      if (all == null) throw StateError('Contribution recovery is unreadable.');
      final entries = (all as JSArray<JSAny>).toDart
          .map(_validated)
          .toList(growable: false);
      if (entries.length > _maxPartitions ||
          (previous == null && entries.length >= _maxPartitions)) {
        throw StateError('Contribution recovery is full.');
      }
      var aggregate = 0;
      for (final entry in entries) {
        // A malformed or undecryptable retained partition cannot be silently
        // replaced or evicted to admit another contribution.
        await _decrypt(_partition(entry.partition), entry);
        aggregate += entry.ciphertext.toDart.lengthInBytes + 12;
      }
      final projected =
          aggregate -
          (previous == null
              ? 0
              : previous.ciphertext.toDart.lengthInBytes + 12) +
          bytes.length +
          28;
      if (projected > _maxAggregateBytes) {
        throw StateError('Contribution recovery is full.');
      }
      final web.CryptoKey key =
          previous?.key ??
          (await web.window.crypto.subtle
                  .generateKey(
                    _KeyAlgorithm(name: 'AES-GCM', length: 256),
                    false,
                    ['encrypt'.toJS, 'decrypt'.toJS].toJS,
                  )
                  .toDart)
              as web.CryptoKey;
      final nonce = Uint8List(12);
      web.window.crypto.getRandomValues(nonce.toJS);
      final revision = expectedRevision + 1;
      final encrypted =
          await web.window.crypto.subtle
                  .encrypt(
                    _parameters(partition, revision, nonce),
                    key,
                    bytes.toJS,
                  )
                  .toDart
              as JSArrayBuffer;
      final record = _EncryptedRecord(
        version: 1,
        partition: partition,
        revision: revision,
        key: key,
        nonce: nonce.toJS,
        ciphertext: encrypted,
      );
      await _transaction(db, 'readwrite', (s) => s.put(record, partition.toJS));
      // Read/decrypt exact bytes after durable transaction acknowledgement;
      // anything uncertain throws and never yields a dispatch permit.
      final saved = await _transaction(
        db,
        'readonly',
        (s) => s.get(partition.toJS),
      );
      if (saved == null) {
        throw StateError('Contribution recovery commit was not acknowledged.');
      }
      final confirmed = await _decrypt(partition, _validated(saved));
      if (confirmed.revision != revision || confirmed.payload != payload) {
        throw StateError('Contribution recovery commit was not acknowledged.');
      }
      return ContributionStoreCasResult(committed: true, snapshot: confirmed);
    } catch (_) {
      throw StateError(
        'Contribution recovery commit could not be confirmed. Check the original request.',
      );
    } finally {
      db.close();
    }
  });

  _CipherAlgorithm _parameters(
    String partition,
    int revision,
    Uint8List nonce,
  ) => _CipherAlgorithm(
    name: 'AES-GCM',
    iv: nonce.toJS,
    additionalData: Uint8List.fromList(
      utf8.encode('$contributionCommandPurpose:$partition:$revision'),
    ).toJS,
    tagLength: 128,
  );
  _EncryptedRecord _validated(JSAny raw) {
    try {
      final r = raw as _EncryptedRecord,
          algorithm = r.key.algorithm as _KeyAlgorithm;
      final usages = (r.key.usages as JSArray<JSString>).toDart
          .map((u) => u.toDart)
          .toList();
      exactJsonInteger(
        r.revision,
        field: 'contribution.store_revision',
        minimum: 1,
      );
      _partition(r.partition);
      if (r.version != 1 ||
          r.key.type != 'secret' ||
          r.key.extractable ||
          algorithm.name != 'AES-GCM' ||
          algorithm.length != 256 ||
          usages.length != 2 ||
          !usages.contains('encrypt') ||
          !usages.contains('decrypt') ||
          r.nonce.toDart.length != 12 ||
          r.ciphertext.toDart.lengthInBytes < 17 ||
          r.ciphertext.toDart.lengthInBytes >
              contributionCommandMaxPayloadBytes + 16) {
        throw StateError('Invalid recovery');
      }
      return r;
    } catch (_) {
      throw StateError('Protected contribution recovery is unreadable.');
    }
  }

  Future<ContributionStoreSnapshot> _decrypt(
    String partition,
    _EncryptedRecord r,
  ) async {
    try {
      if (r.partition != partition) {
        throw StateError('Invalid recovery partition.');
      }
      final decrypted =
          await web.window.crypto.subtle
                  .decrypt(
                    _parameters(partition, r.revision, r.nonce.toDart),
                    r.key,
                    r.ciphertext,
                  )
                  .toDart
              as JSArrayBuffer;
      final bytes = decrypted.toDart.asUint8List();
      if (bytes.isEmpty || bytes.length > contributionCommandMaxPayloadBytes) {
        throw StateError('Invalid recovery');
      }
      return ContributionStoreSnapshot(
        partitionId: partition,
        revision: r.revision,
        payload: utf8.decode(bytes),
      );
    } catch (_) {
      throw StateError('Protected contribution recovery is unreadable.');
    }
  }

  Future<web.IDBDatabase> _open() async {
    final result = Completer<web.IDBDatabase>();
    try {
      final request = web.window.indexedDB.open(_databaseName, 1);
      request.onupgradeneeded = ((web.Event e) {
        try {
          final db = request.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(_storeName)) {
            db.createObjectStore(_storeName);
          }
        } catch (_) {
          request.transaction?.abort();
        }
      }).toJS;
      request.onsuccess = ((web.Event e) {
        final db = request.result as web.IDBDatabase;
        if (result.isCompleted) {
          db.close();
          return;
        }
        db.onversionchange = ((web.Event e) {
          db.close();
        }).toJS;
        result.complete(db);
      }).toJS;
      void fail(web.Event e) {
        if (!result.isCompleted) {
          result.completeError(
            StateError('Protected contribution recovery is unavailable.'),
          );
        }
      }

      request.onerror = fail.toJS;
      request.onblocked = fail.toJS;
    } catch (_) {
      throw StateError('Protected contribution recovery is unavailable.');
    }
    return result.future;
  }

  Future<JSAny?> _transaction(
    web.IDBDatabase db,
    String mode,
    web.IDBRequest Function(web.IDBObjectStore) action,
  ) async {
    final result = Completer<JSAny?>();
    web.IDBTransaction? transaction;
    try {
      transaction = db.transaction(
        _storeName.toJS,
        mode,
        web.IDBTransactionOptions(durability: 'strict'),
      );
      JSAny? value;
      transaction.oncomplete = ((web.Event e) {
        if (!result.isCompleted) result.complete(value);
      }).toJS;
      void fail(web.Event e) {
        if (!result.isCompleted) {
          result.completeError(
            StateError('Contribution recovery did not commit.'),
          );
        }
      }

      transaction.onabort = fail.toJS;
      transaction.onerror = fail.toJS;
      final request = action(transaction.objectStore(_storeName));
      request.onsuccess = ((web.Event e) {
        value = request.result;
      }).toJS;
    } catch (_) {
      try {
        transaction?.abort();
      } catch (_) {}
      if (!result.isCompleted) {
        result.completeError(
          StateError('Protected contribution recovery is unavailable.'),
        );
      }
    }
    return result.future;
  }
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
    String partition,
    int revision,
    web.CryptoKey key,
    JSUint8Array nonce,
    JSArrayBuffer ciphertext,
  });
  external int get version;
  external String get partition;
  external int get revision;
  external web.CryptoKey get key;
  external JSUint8Array get nonce;
  external JSArrayBuffer get ciphertext;
}
