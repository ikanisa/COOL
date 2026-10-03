@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_models.dart';
import 'package:flutter_test/flutter_test.dart';

@JS('window.localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

@JS('navigator.locks')
external _LockManager get _locks;
extension type _LockManager(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(String name, JSFunction callback);
}

String _id(int n) => '99840000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
final _owner = adminReceiptPrincipalOwnerDigest(_id(20));
final _otherOwner = adminReceiptPrincipalOwnerDigest(_id(21));
String _prefix(String owner) =>
    'collect.admin.receipt-principal.recovery.v3.$owner.';
String _key(AdminReceiptPrincipalCheckpoint original) =>
    '${_prefix(original.ownerDigest)}${original.requestId}';

// Public P-256 generator-point fingerprint used in the isolated v3 SQL fixture
// (receipt_operations_enrollment_workflow_uat.py). No private key is used.
// All browser UUIDs, clock values and response maps below are synthetic; this
// test establishes browser persistence/exclusion, never backend authorization.
const _fingerprint =
    '5cd252fb0ce8932436faf8ccd1040981b89ee4ad6b9fe9e2a2b7e71aacb27cd3';

AdminReceiptPrincipalIntent _intent(
  int request, {
  bool revoke = false,
  int principal = 9,
}) {
  final created = DateTime.now().toUtc();
  final expires = created.add(const Duration(seconds: 90));
  final identityExpires = created.add(const Duration(days: 1));
  return revoke
      ? AdminReceiptPrincipalIntent.revoke(
          requestId: _id(request),
          principalId: _id(principal),
          keySha256: _fingerprint,
          createdAt: created,
          requestExpiresAt: expires,
          identityExpiresAt: identityExpires,
          reason: 'Synthetic browser key retirement',
        )
      : AdminReceiptPrincipalIntent.activate(
          requestId: _id(request),
          principalId: _id(principal),
          keySha256: _fingerprint,
          createdAt: created,
          requestExpiresAt: expires,
          identityExpiresAt: identityExpires,
        );
}

Map<String, dynamic> _receipt(AdminReceiptPrincipalBinding binding) => {
  'contract_version': 3,
  'action': binding.action.name,
  'request_id': binding.requestId,
  'principal_id': binding.principalId,
  'state_at_action': binding.action.resultState.name,
  'scope': 'rw_receipt_operations',
  'key_sha256': binding.keySha256,
  'identity_expires_at': operationsUtc(binding.identityExpiresAt),
  'recorded_at': operationsUtc(binding.createdAt),
  'request_expires_at': operationsUtc(binding.requestExpiresAt),
  if (binding.action == AdminReceiptPrincipalAction.revoke)
    'reason_sha256': binding.reasonSha256,
};

Map<String, dynamic> _lookup(AdminReceiptPrincipalBinding binding) {
  final checked = DateTime.now().toUtc();
  return {
    'contract_version': 3,
    'request_id': binding.requestId,
    'action': binding.action.name,
    'status': 'recorded',
    'checked_at': operationsUtc(checked),
    'sample_valid_until': operationsUtc(
      checked.add(const Duration(seconds: 60)),
    ),
    'request_expires_at': operationsUtc(binding.requestExpiresAt),
    'receipt': _receipt(binding),
  };
}

/// Test-only holder uses the browser's actual owner-scoped exclusive lock.
class _HeldLock {
  _HeldLock(this.release, this.done);
  final Completer<JSAny?> release;
  final Future<JSAny?> done;
  Future<void> close() async {
    if (!release.isCompleted) release.complete(null);
    await done;
  }
}

Future<_HeldLock> _hold() async {
  final entered = Completer<void>(), release = Completer<JSAny?>();
  final done = _locks
      .request(
        '${_prefix(_owner)}exclusive',
        ((JSAny? lock) {
          if (lock == null) throw StateError('Exclusive lock unavailable');
          entered.complete();
          return release.future.toJS;
        }).toJS,
      )
      .toDart;
  await entered.future.timeout(const Duration(seconds: 2));
  return _HeldLock(release, done);
}

void _clearSyntheticNamespace() {
  final keys = <String>[];
  for (var i = 0; i < _storage.length; i++) {
    final key = _storage.key(i);
    if (key != null &&
        (key.startsWith(_prefix(_owner)) ||
            key.startsWith(_prefix(_otherOwner)))) {
      keys.add(key);
    }
  }
  for (final key in keys) {
    _storage.removeItem(key);
  }
}

Future<bool> _publish(
  AdminReceiptPrincipalCheckpointStore store,
  AdminReceiptPrincipalCheckpoint original,
) async {
  try {
    await store.write(
      original.ownerDigest,
      original.requestId,
      original.encode(),
      isCurrent: () => true,
    );
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  setUp(_clearSyntheticNamespace);
  tearDown(_clearSyntheticNamespace);

  test(
    'real store reload uses original lookup only and retains resolved bytes',
    () async {
      final intent = _intent(1, revoke: true);
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        intent,
      );
      final firstStore = browserAdminReceiptPrincipalCheckpointStore()!;
      var sends = 0, lookups = 0;
      final first = AdminReceiptPrincipalController(
        ownerDigest: _owner,
        store: firstStore,
        now: () => DateTime.now().toUtc(),
        isCurrent: () => true,
        preflight: (_) async => true,
        send: (_) async {
          expect(_storage.getItem(_key(original)), original.encode());
          expect(await firstStore.read(_owner), [original.encode()]);
          sends++;
          throw StateError('Synthetic unknown transport outcome');
        },
        lookup: (_) async => throw StateError('No automatic lookup'),
      );
      await first.ready;
      await first.submit(intent);
      expect(first.state.pending.single.digest, original.digest);
      first.dispose();

      final restarted = AdminReceiptPrincipalController(
        ownerDigest: _owner,
        store: browserAdminReceiptPrincipalCheckpointStore()!,
        now: () => DateTime.now().toUtc(),
        isCurrent: () => true,
        preflight: (_) async => throw StateError('No automatic preflight'),
        send: (_) async => throw StateError('Restored originals cannot send'),
        lookup: (binding) async {
          expect(binding, isNot(isA<AdminReceiptPrincipalIntent>()));
          expect(binding.toJson(), original.binding.toJson());
          lookups++;
          return _lookup(binding);
        },
      );
      addTearDown(restarted.dispose);
      await restarted.ready;
      await restarted.reconcile(restarted.state.pending.single);
      expect(restarted.state.pending, isEmpty);
      expect(restarted.state.receipt?.requestId, intent.requestId);
      expect(sends, 1);
      expect(lookups, 1);
      expect(_storage.getItem(_key(original)), original.encode());
      final marker = jsonDecode(
        _storage.getItem('${_key(original)}.resolution')!,
      );
      expect(marker['original_sha256'], original.digest);
      expect(marker['status'], 'recorded');
      expect(
        original.encode(),
        isNot(contains('Synthetic browser key retirement')),
      );
      expect(original.encode(), isNot(contains('public_key_spki')));
      expect(await firstStore.read(_otherOwner), isEmpty);
      expect(await firstStore.read(_owner), isEmpty);
    },
  );

  test(
    'actual lock serializes exact-UUID concurrent publication and prevents overwrite',
    () async {
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1),
      );
      final first = browserAdminReceiptPrincipalCheckpointStore()!;
      final second = browserAdminReceiptPrincipalCheckpointStore()!;
      final results = await Future.wait([
        _publish(first, original),
        _publish(second, original),
      ]);
      expect(results.where((p) => p).length, 1);
      expect(await second.read(_owner), [original.encode()]);
      await first.resolve(original, 'recorded', isCurrent: () => true);
      expect(await _publish(second, original), isFalse);
      expect(_storage.getItem(_key(original)), original.encode());
      expect(await second.read(_owner), isEmpty);
    },
  );

  test(
    'actual lock refuses distinct pending revoke UUIDs for one target',
    () async {
      final first = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1, revoke: true),
      );
      final second = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(2, revoke: true),
      );
      final results = await Future.wait([
        _publish(browserAdminReceiptPrincipalCheckpointStore()!, first),
        _publish(browserAdminReceiptPrincipalCheckpointStore()!, second),
      ]);
      expect(results.where((p) => p).length, 1);
      final retained = await browserAdminReceiptPrincipalCheckpointStore()!
          .read(_owner);
      expect(retained.length, 1);
      expect(retained.single, anyOf(first.encode(), second.encode()));
    },
  );

  test(
    'urgent different-target revoke can publish alongside original activation',
    () async {
      final store = browserAdminReceiptPrincipalCheckpointStore()!;
      final activation = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1),
      );
      final revoke = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(2, revoke: true),
      );
      expect(await _publish(store, activation), isTrue);
      expect(await _publish(store, revoke), isTrue);
      expect(
        await _publish(
          store,
          AdminReceiptPrincipalCheckpoint.fromIntent(_owner, _intent(3)),
        ),
        isFalse,
      );
      expect((await store.read(_owner)).length, 2);
    },
  );

  test(
    'authority-lost queued publication acquires no permission to write',
    () async {
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1),
      );
      final store = browserAdminReceiptPrincipalCheckpointStore()!;
      final held = await _hold();
      addTearDown(held.close);
      var current = true;
      final refused = expectLater(
        store.write(
          _owner,
          original.requestId,
          original.encode(),
          isCurrent: () => current,
        ),
        throwsA(anything),
      );
      current = false;
      await held.close();
      await refused;
      expect(_storage.getItem(_key(original)), isNull);
      expect(await store.read(_owner), isEmpty);
    },
  );

  test(
    'five-second aborted lock acquisition never publishes after eventual release',
    () async {
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1),
      );
      final store = browserAdminReceiptPrincipalCheckpointStore()!;
      final held = await _hold();
      addTearDown(held.close);
      await expectLater(
        store.write(
          _owner,
          original.requestId,
          original.encode(),
          isCurrent: () => true,
        ),
        throwsA(anything),
      );
      expect(_storage.getItem(_key(original)), isNull);
      await held.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_storage.getItem(_key(original)), isNull);
      expect(await store.read(_owner), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    'controller timeout closes queued publication before lock becomes available',
    () async {
      final intent = _intent(1);
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        intent,
      );
      var sends = 0;
      final controller = AdminReceiptPrincipalController(
        ownerDigest: _owner,
        store: browserAdminReceiptPrincipalCheckpointStore()!,
        now: () => DateTime.now().toUtc(),
        isCurrent: () => true,
        preflight: (_) async => true,
        send: (_) async {
          sends++;
          return _receipt(intent);
        },
        lookup: (_) async => throw StateError('No automatic lookup'),
        timeout: const Duration(milliseconds: 40),
      );
      addTearDown(controller.dispose);
      await controller.ready;
      final held = await _hold();
      addTearDown(held.close);
      await controller.submit(intent);
      expect(controller.state.storageBlocked, isTrue);
      await held.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sends, 0);
      expect(_storage.getItem(_key(original)), isNull);
    },
  );

  for (final defect in [
    'changed-original',
    'changed-marker',
    'orphan-marker',
  ]) {
    test('$defect actual browser bytes fail closed on reload', () async {
      final store = browserAdminReceiptPrincipalCheckpointStore()!;
      final original = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(1),
      );
      expect(await _publish(store, original), isTrue);
      await store.resolve(original, 'recorded', isCurrent: () => true);
      if (defect == 'changed-original') {
        _storage.setItem(_key(original), '${original.encode()} ');
      } else if (defect == 'changed-marker') {
        final key = '${_key(original)}.resolution';
        final row = jsonDecode(_storage.getItem(key)!) as Map<String, dynamic>;
        row['original_sha256'] = '0' * 64;
        _storage.setItem(key, jsonEncode(row));
      } else {
        _storage.removeItem(_key(original));
      }
      await expectLater(store.read(_owner), throwsA(anything));
      final replacement = AdminReceiptPrincipalCheckpoint.fromIntent(
        _owner,
        _intent(2),
      );
      expect(await _publish(store, replacement), isFalse);
      expect(_storage.getItem(_key(replacement)), isNull);
    });
  }
}
