import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_models.dart';
import 'package:flutter_test/flutter_test.dart';

String _id(int n) => '99830000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
final _at = DateTime.utc(2026, 10, 1, 13);
final _owner = adminReceiptPrincipalOwnerDigest(_id(20));
const _key = '5cd252fb0ce8932436faf8ccd1040981b89ee4ad6b9fe9e2a2b7e71aacb27cd3';
// Public generator point from the isolated SQL fixture; no private key is used.
const _spki =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEaxfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBoN79R9Q==';
AdminReceiptPrincipalIntent _intent(
  int request, {
  bool revoke = false,
  int principal = 9,
  bool expired = false,
}) {
  final expiry = expired
      ? _at.subtract(const Duration(days: 1))
      : _at.add(const Duration(days: 1));
  return revoke
      ? AdminReceiptPrincipalIntent.revoke(
          requestId: _id(request),
          createdAt: _at,
          requestExpiresAt: _at.add(const Duration(seconds: 90)),
          identityExpiresAt: expiry,
          principalId: _id(principal),
          keySha256: _key,
          reason: 'Retire suspect operations key',
        )
      : AdminReceiptPrincipalIntent.activate(
          requestId: _id(request),
          createdAt: _at,
          requestExpiresAt: _at.add(const Duration(seconds: 90)),
          identityExpiresAt: expiry,
          principalId: _id(principal),
          keySha256: _key,
        );
}

Map<String, dynamic> _receipt(AdminReceiptPrincipalBinding binding) => {
  'contract_version': 3,
  'action': binding.action.name,
  'request_id': binding.requestId,
  'principal_id': binding.principalId ?? _id(9),
  'state_at_action': binding.action.resultState.name,
  'scope': 'rw_receipt_operations',
  'key_sha256': binding.keySha256,
  'identity_expires_at': operationsUtc(binding.identityExpiresAt),
  'recorded_at': operationsUtc(binding.createdAt),
  'request_expires_at': operationsUtc(binding.requestExpiresAt),
  if (binding.action == AdminReceiptPrincipalAction.revoke)
    'reason_sha256': binding.reasonSha256,
};
Map<String, dynamic> _lookup(
  AdminReceiptPrincipalBinding binding,
  String status,
  DateTime checked, {
  Map<String, dynamic>? receipt,
}) => {
  'contract_version': 3,
  'request_id': binding.requestId,
  'action': status == 'recorded' ? binding.action.name : null,
  'status': status,
  'checked_at': operationsUtc(checked),
  'sample_valid_until': operationsUtc(checked.add(const Duration(seconds: 60))),
  'request_expires_at': status == 'recorded'
      ? operationsUtc(binding.requestExpiresAt)
      : null,
  'receipt': status == 'recorded' ? receipt ?? _receipt(binding) : null,
};

class PrincipalMemoryStore implements AdminReceiptPrincipalCheckpointStore {
  final originals = <String, String>{}, resolutions = <String, String>{};
  bool failRead = false,
      failWrite = false,
      failResolve = false,
      dropWrite = false,
      corruptReadback = false;
  Completer<void>? writeGate, resolveGate;
  void Function()? onWrite;
  Future<void> _tail = Future.value();
  String _key(String owner, String request) => '$owner:$request';
  Future<T> _exclusive<T>(FutureOr<T> Function() work) async {
    final prior = _tail, next = Completer<void>();
    _tail = next.future;
    await prior;
    try {
      return await work();
    } finally {
      next.complete();
    }
  }

  List<String> _pending(String owner) {
    if (failRead) throw StateError('PRIVATE_STORAGE_CANARY');
    final prefix = '$owner:';
    for (final key in resolutions.keys.where((key) => key.startsWith(prefix))) {
      if (!originals.containsKey(key)) {
        throw const FormatException('Orphan marker');
      }
    }
    final result = <String>[];
    for (final entry in originals.entries.where(
      (e) => e.key.startsWith(prefix),
    )) {
      final checkpoint = AdminReceiptPrincipalCheckpoint.parse(
        entry.value,
        owner,
      );
      if (entry.key != _key(owner, checkpoint.requestId)) {
        throw const FormatException('Misbound key');
      }
      final marker = resolutions[entry.key];
      if (marker == null) {
        result.add(entry.value);
      } else if (!marker.startsWith('${checkpoint.digest}:')) {
        throw const FormatException('Changed original');
      }
    }
    return result;
  }

  @override
  Future<List<String>> read(String ownerDigest) =>
      _exclusive(() => _pending(ownerDigest));
  @override
  Future<void> write(
    String ownerDigest,
    String requestId,
    String encoded, {
    required bool Function() isCurrent,
  }) => _exclusive(() async {
    if (writeGate != null) await writeGate!.future;
    if (!isCurrent() || failWrite) throw StateError('PRIVATE_STORAGE_CANARY');
    final checkpoint = AdminReceiptPrincipalCheckpoint.parse(
          encoded,
          ownerDigest,
        ),
        key = _key(ownerDigest, requestId);
    final pending = _pending(ownerDigest)
        .map((e) => AdminReceiptPrincipalCheckpoint.parse(e, ownerDigest))
        .toList();
    if (checkpoint.requestId != requestId ||
        originals.containsKey(key) ||
        !adminReceiptPrincipalMayPublish(pending, checkpoint.binding)) {
      throw const FormatException('Original blocked');
    }
    if (!dropWrite) originals[key] = corruptReadback ? '{}' : encoded;
    onWrite?.call();
  });
  @override
  Future<void> resolve(
    AdminReceiptPrincipalCheckpoint checkpoint,
    String status, {
    required bool Function() isCurrent,
  }) => _exclusive(() async {
    if (resolveGate != null) await resolveGate!.future;
    if (!isCurrent() ||
        failResolve ||
        originals[_key(checkpoint.ownerDigest, checkpoint.requestId)] !=
            checkpoint.encode()) {
      throw StateError('PRIVATE_STORAGE_CANARY');
    }
    resolutions[_key(checkpoint.ownerDigest, checkpoint.requestId)] =
        '${checkpoint.digest}:$status';
  });
  Future<void> retain(AdminReceiptPrincipalIntent intent) async {
    final value = AdminReceiptPrincipalCheckpoint.fromIntent(_owner, intent);
    await write(_owner, value.requestId, value.encode(), isCurrent: () => true);
  }
}

AdminReceiptPrincipalController _controller(
  PrincipalMemoryStore? store, {
  DateTime Function()? now,
  bool Function()? current,
  Future<bool> Function(AdminReceiptPrincipalIntent)? preflight,
  Future<Map<String, dynamic>> Function(AdminReceiptPrincipalIntent)? send,
  Future<Map<String, dynamic>> Function(AdminReceiptPrincipalBinding)? lookup,
  Duration timeout = const Duration(seconds: 15),
}) => AdminReceiptPrincipalController(
  ownerDigest: _owner,
  store: store,
  now: now ?? () => _at,
  isCurrent: current ?? () => true,
  preflight: preflight ?? (_) async => true,
  send: send ?? (binding) async => _receipt(binding),
  lookup: lookup ?? (binding) async => _lookup(binding, 'in_progress', _at),
  timeout: timeout,
);

void main() {
  test(
    'bookmark isolates owner and retains only safe original binding, never mutation material',
    () {
      final intent = _intent(1, revoke: true),
          original = AdminReceiptPrincipalCheckpoint.fromIntent(_owner, intent),
          encoded = original.encode();
      expect(
        AdminReceiptPrincipalCheckpoint.parse(encoded, _owner).digest,
        original.digest,
      );
      expect(original.binding, isNot(isA<AdminReceiptPrincipalIntent>()));
      expect(encoded, isNot(contains(intent.reason!)));
      expect(encoded, isNot(contains('p_reason')));
      expect(encoded, isNot(contains('public_key')));
      expect(original.binding.reasonSha256, intent.reasonSha256);
      expect(
        () => AdminReceiptPrincipalCheckpoint.parse(
          encoded,
          adminReceiptPrincipalOwnerDigest(_id(21)),
        ),
        throwsFormatException,
      );
      final enroll = AdminReceiptPrincipalIntent.enroll(
        requestId: _id(2),
        createdAt: _at,
        requestExpiresAt: _at.add(const Duration(seconds: 90)),
        identityExpiresAt: _at.add(const Duration(days: 1)),
        publicKey: AdminReceiptPrincipalPublicKey.parse({
          'contract_version': 2,
          'scope': 'rw_receipt_operations',
          'public_key_spki_base64': _spki,
          'key_sha256': _key,
        }),
      );
      expect(
        AdminReceiptPrincipalCheckpoint.fromIntent(_owner, enroll).encode(),
        isNot(contains(_spki)),
      );
    },
  );
  for (final field in [
    'action',
    'request_id',
    'principal_id',
    'key_sha256',
    'identity_expires_at',
    'created_at',
    'request_expires_at',
    'reason_sha256',
  ]) {
    test('bookmark refuses invalid $field and exact JSON representation', () {
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1, revoke: true),
      );
      final raw = jsonDecode(original.encode()) as Map<String, dynamic>;
      (raw['binding'] as Map<String, dynamic>)[field] = 'invalid';
      expect(
        () => AdminReceiptPrincipalCheckpoint.parse(jsonEncode(raw), _owner),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptPrincipalCheckpoint.parse(
          '${original.encode()} ',
          _owner,
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'duplicate keys, extra private payload and oversized bookmark refuse',
    () {
      final encoded = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1),
      ).encode();
      for (final value in [
        '{"version":3,${encoded.substring(1)}',
        '${encoded.substring(0, encoded.length - 1)},"reason":"PRIVATE"}',
        'x' * 2049,
      ]) {
        expect(
          () => AdminReceiptPrincipalCheckpoint.parse(value, _owner),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'durable original exists and is read back before the only send',
    () async {
      final store = PrincipalMemoryStore();
      var calls = 0;
      final controller = _controller(
        store,
        send: (intent) async {
          calls++;
          expect(
            (await store.read(_owner)).single,
            AdminReceiptPrincipalCheckpoint.fromIntent(_owner, intent).encode(),
          );
          return _receipt(intent);
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.submit(_intent(1));
      expect(calls, 1);
      expect(controller.state.pending, isEmpty);
      expect(controller.state.receipt?.requestId, _id(1));
      expect(store.originals.length, 1);
      expect(store.resolutions.length, 1);
      await controller.submit(_intent(1));
      expect(calls, 1);
      expect(controller.state.storageBlocked, true);
    },
  );
  for (final failure in ['unavailable', 'write', 'drop', 'corrupt']) {
    test('$failure recovery storage prevents all transport', () async {
      final store = failure == 'unavailable' ? null : PrincipalMemoryStore();
      if (failure == 'write') store!.failWrite = true;
      if (failure == 'drop') store!.dropWrite = true;
      if (failure == 'corrupt') store!.corruptReadback = true;
      var calls = 0;
      final controller = _controller(
        store,
        send: (intent) async {
          calls++;
          return _receipt(intent);
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.submit(_intent(1));
      expect(calls, 0);
      expect(controller.state.storageBlocked, true);
      expect(controller.state.message, isNot(contains('CANARY')));
    });
  }
  test(
    'reload restores binding only and manually reconciles original without any send',
    () async {
      final store = PrincipalMemoryStore();
      await store.retain(_intent(1));
      var sends = 0, lookups = 0;
      final controller = _controller(
        store,
        send: (_) async {
          sends++;
          throw StateError('must not replay');
        },
        lookup: (binding) async {
          lookups++;
          expect(binding, isNot(isA<AdminReceiptPrincipalIntent>()));
          return _lookup(binding, 'recorded', _at);
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.reconcile(controller.state.pending.single);
      expect(sends, 0);
      expect(lookups, 1);
      expect(controller.state.pending, isEmpty);
      expect(store.originals.length, 1);
    },
  );
  test(
    'uncertain send preserves original across reload and blocks enrollment/activation replay',
    () async {
      final store = PrincipalMemoryStore();
      var sends = 0;
      final first = _controller(
        store,
        send: (_) async {
          sends++;
          throw StateError('PRIVATE_BACKEND_CANARY');
        },
      );
      await first.ready;
      await first.submit(_intent(1));
      expect(first.state.pending.single.requestId, _id(1));
      expect(first.state.message, isNot(contains('CANARY')));
      first.dispose();
      final restarted = _controller(
        store,
        send: (_) async {
          sends++;
          throw StateError('must not send');
        },
      );
      addTearDown(restarted.dispose);
      await restarted.ready;
      await restarted.submit(_intent(1));
      await restarted.submit(_intent(2));
      expect(sends, 1);
      expect(restarted.state.pending.single.requestId, _id(1));
    },
  );
  test(
    'urgent revoke proceeds beside pending activation but duplicate target revoke is blocked',
    () async {
      final store = PrincipalMemoryStore();
      await store.retain(_intent(1));
      var sends = 0;
      final controller = _controller(
        store,
        send: (_) async {
          sends++;
          throw StateError('unknown');
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      expect(controller.canBeginRevocation(_id(9)), isTrue);
      await controller.submit(_intent(2, revoke: true));
      expect(controller.canBeginRevocation(_id(9)), isFalse);
      expect(controller.canBeginRevocation(_id(10)), isTrue);
      await controller.submit(_intent(3, revoke: true));
      await controller.submit(_intent(4));
      expect(sends, 1);
      expect(controller.state.pending.map((p) => p.requestId), [
        _id(1),
        _id(2),
      ]);
    },
  );
  test(
    'urgent revoke can run while unrelated original HTTP is still outstanding',
    () async {
      final store = PrincipalMemoryStore(),
          entered = Completer<void>(),
          response = Completer<Map<String, dynamic>>();
      var sends = 0;
      final controller = _controller(
        store,
        send: (intent) async {
          sends++;
          if (intent.action == AdminReceiptPrincipalAction.activate) {
            entered.complete();
            return response.future;
          }
          return _receipt(intent);
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      final first = controller.submit(_intent(1));
      await entered.future;
      expect(controller.state.busy, isTrue);
      expect(controller.canBeginRevocation(_id(9)), isTrue);
      await controller.submit(_intent(2, revoke: true));
      expect(sends, 2);
      expect(controller.state.pending.single.requestId, _id(1));
      response.complete(_receipt(_intent(1)));
      await first;
      expect(controller.state.pending, isEmpty);
      expect(store.originals.length, 2);
    },
  );
  test(
    'different controllers cannot publish a duplicate target pending revoke',
    () async {
      final store = PrincipalMemoryStore();
      var sends = 0;
      final first = _controller(
            store,
            send: (_) async {
              sends++;
              throw StateError('unknown');
            },
          ),
          second = _controller(
            store,
            send: (_) async {
              sends++;
              throw StateError('unknown');
            },
          );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await Future.wait([first.ready, second.ready]);
      await Future.wait([
        first.submit(_intent(1, revoke: true)),
        second.submit(_intent(2, revoke: true)),
      ]);
      expect(sends, 1);
      expect(store.originals.length, 1);
    },
  );
  for (final status in ['not_recorded', 'in_progress']) {
    test('$status before deadline keeps original pending', () async {
      final store = PrincipalMemoryStore();
      await store.retain(_intent(1));
      final controller = _controller(
        store,
        lookup: (binding) async =>
            _lookup(binding, status, _at.add(const Duration(seconds: 10))),
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.reconcile(controller.state.pending.single);
      expect(controller.state.pending.length, 1);
      expect(store.resolutions, isEmpty);
    });
  }
  test(
    'server check past deadline cannot close absence while local deadline is still open',
    () async {
      final store = PrincipalMemoryStore();
      await store.retain(_intent(1));
      final controller = _controller(
        store,
        now: () => _at.add(const Duration(seconds: 85)),
        lookup: (binding) async => _lookup(
          binding,
          'not_recorded',
          _at.add(const Duration(seconds: 90)),
        ),
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.reconcile(controller.state.pending.single);
      expect(controller.state.pending.length, 1);
      expect(store.resolutions, isEmpty);
    },
  );
  test(
    'fresh absence at retained deadline closes marker without deleting original or replay',
    () async {
      final store = PrincipalMemoryStore();
      await store.retain(_intent(1));
      var sends = 0;
      final controller = _controller(
        store,
        now: () => _at.add(const Duration(seconds: 90)),
        send: (_) async {
          sends++;
          throw StateError('no replay');
        },
        lookup: (binding) async => _lookup(
          binding,
          'not_recorded',
          _at.add(const Duration(seconds: 90)),
        ),
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.reconcile(controller.state.pending.single);
      expect(controller.state.pending, isEmpty);
      expect(store.originals.length, 1);
      expect(
        store.resolutions.values.single,
        endsWith(':not_recorded_after_deadline'),
      );
      expect(sends, 0);
    },
  );
  for (final defect in ['stale', 'wrong-key', 'unexpected-field']) {
    test('$defect lookup cannot resolve an original', () async {
      final store = PrincipalMemoryStore();
      await store.retain(_intent(1));
      final controller = _controller(
        store,
        now: () => _at.add(const Duration(seconds: 150)),
        lookup: (binding) async {
          final row = _lookup(
            binding,
            'recorded',
            _at.add(Duration(seconds: defect == 'stale' ? 90 : 150)),
          );
          if (defect == 'wrong-key') {
            (row['receipt'] as Map<String, dynamic>)['key_sha256'] = '0' * 64;
          }
          if (defect == 'unexpected-field') row['token'] = 'PRIVATE';
          return row;
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.reconcile(controller.state.pending.single);
      expect(controller.state.pending.length, 1);
      expect(store.resolutions, isEmpty);
    });
  }
  test(
    'resolution persistence failure retains unknown original and no recorded UI receipt',
    () async {
      final store = PrincipalMemoryStore()..failResolve = true,
          controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.submit(_intent(1));
      expect(controller.state.pending.length, 1);
      expect(controller.state.receipt, isNull);
      expect(store.originals.length, 1);
    },
  );
  test(
    'authority departure and A-B-A suppress late acknowledgement permanently',
    () async {
      final store = PrincipalMemoryStore(),
          entered = Completer<void>(),
          response = Completer<Map<String, dynamic>>();
      var current = true;
      final controller = _controller(
        store,
        current: () => current,
        send: (_) async {
          entered.complete();
          return response.future;
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      final action = controller.submit(_intent(1));
      await entered.future;
      current = false;
      expect(controller.canSubmit(_intent(2, revoke: true)), false);
      controller.depart();
      current = true;
      response.complete(_receipt(_intent(1)));
      await action;
      expect(controller.state.departed, true);
      expect(controller.state.receipt, isNull);
      expect(store.resolutions, isEmpty);
      expect(store.originals.length, 1);
      expect(controller.canSubmit(_intent(2, revoke: true)), false);
    },
  );
  test(
    'preflight refusal and expired deadline never publish or send',
    () async {
      for (final advances in [false, true]) {
        final store = PrincipalMemoryStore();
        var time = _at, sends = 0;
        final controller = _controller(
          store,
          now: () => time,
          preflight: (_) async {
            if (advances) time = _at.add(const Duration(seconds: 90));
            return advances;
          },
          send: (intent) async {
            sends++;
            return _receipt(intent);
          },
        );
        await controller.ready;
        await controller.submit(_intent(1));
        expect(sends, 0);
        expect(store.originals, isEmpty);
        controller.dispose();
      }
    },
  );
  test(
    'deadline is checked again after durable write and before transport',
    () async {
      final store = PrincipalMemoryStore();
      var time = _at, sends = 0;
      store.onWrite = () => time = _at.add(const Duration(seconds: 90));
      final controller = _controller(
        store,
        now: () => time,
        send: (intent) async {
          sends++;
          return _receipt(intent);
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.submit(_intent(1));
      expect(sends, 0);
      expect(controller.state.pending.length, 1);
      expect(store.originals.length, 1);
    },
  );
  test(
    'bounded transport timeout retains original and ignores late success',
    () async {
      final store = PrincipalMemoryStore(),
          response = Completer<Map<String, dynamic>>();
      var sends = 0;
      final controller = _controller(
        store,
        timeout: const Duration(milliseconds: 20),
        send: (_) async {
          sends++;
          return response.future;
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.submit(_intent(1));
      expect(sends, 1);
      expect(controller.state.pending.length, 1);
      response.complete(_receipt(_intent(1)));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(store.resolutions, isEmpty);
      expect(controller.state.receipt, isNull);
    },
  );
  test(
    'timed out queued publication cannot write later or reach transport',
    () async {
      final gate = Completer<void>(),
          store = PrincipalMemoryStore()..writeGate = gate;
      var sends = 0;
      final controller = _controller(
        store,
        timeout: const Duration(milliseconds: 20),
        send: (intent) async {
          sends++;
          return _receipt(intent);
        },
      );
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.submit(_intent(1));
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(store.originals, isEmpty);
      expect(sends, 0);
      expect(controller.state.storageBlocked, true);
    },
  );
  test(
    'expired identity is retained for revocation but not accepted as an activation draft',
    () async {
      final store = PrincipalMemoryStore(), controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.ready;
      await controller.submit(_intent(1, revoke: true, expired: true));
      expect(
        controller.state.receipt?.stateAtAction,
        AdminReceiptPrincipalState.revoked,
      );
      expect(() => _intent(2, expired: true), throwsFormatException);
    },
  );
  test(
    'bounded pending inventory and changed marker fail closed on reload',
    () async {
      final store = PrincipalMemoryStore();
      for (var i = 1; i <= 51; i++) {
        final checkpoint = AdminReceiptPrincipalCheckpoint.fromIntent(
          _owner,
          _intent(i, revoke: true, principal: 100 + i),
        );
        store.originals[store._key(_owner, checkpoint.requestId)] = checkpoint
            .encode();
      }
      final controller = _controller(store);
      addTearDown(controller.dispose);
      await controller.ready;
      expect(controller.state.storageBlocked, true);
      store.originals.clear();
      final checkpoint = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1),
      );
      store.originals[store._key(_owner, checkpoint.requestId)] = checkpoint
          .encode();
      store.resolutions[store._key(_owner, checkpoint.requestId)] = '0' * 64;
      await controller.reload();
      expect(controller.state.storageBlocked, true);
      expect(controller.canSubmit(_intent(2, revoke: true)), false);
    },
  );
}
