import 'dart:async';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_governed_settings_models.dart';
import 'package:collect_app/admin/core/admin_governed_settings_checkpoint.dart';
import 'package:collect_app/admin/core/admin_governed_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/settings_fixture.dart' as f;

void main() {
  late f.MemorySettingsStore store;
  late f.SettingsApiFake api;
  late DateTime now;
  late bool current, manage;
  late AdminSessionScope session;
  late AdminSettingsActionController controller;
  final owner = adminSettingsOwnerDigest(f.actor);
  AdminSettingsActionController create() => AdminSettingsActionController(
    ownerDigest: owner,
    store: store,
    api: api,
    now: () => now,
    scope: () => session,
    canManage: (_) => manage,
    isCurrent: () => current,
  );
  setUp(() {
    store = f.MemorySettingsStore();
    api = f.SettingsApiFake();
    now = f.at;
    current = true;
    manage = true;
    session = f.scope;
    controller = create();
  });
  tearDown(() => controller.dispose());
  test(
    'immutable metadata is durably admitted before single mutation and resolved after acknowledgement',
    () async {
      api.onUpdate = (i) async {
        expect(
          store.read(owner).single,
          AdminSettingsBookmark.fromPrepared(owner, i).encode(),
        );
        return AdminSettingsReceipt.parse(f.receiptJson(i));
      };
      await controller.submit(f.intent());
      expect(api.updates, 1);
      expect(controller.state.pending, isEmpty);
      expect(store.originals.length, 1);
      expect(store.resolutions.length, 1);
      expect(controller.state.receipt, isNotNull);
    },
  );
  for (final failure in ['write', 'readback', 'corrupt_existing']) {
    test('$failure blocks HTTP with redacted storage failure', () async {
      if (failure == 'write') store.failWrite = true;
      if (failure == 'readback') store.dropWrite = true;
      if (failure == 'corrupt_existing') {
        store.originals['corrupt'] = 'PRIVATE_STORAGE_CANARY';
        controller.reload();
      }
      await controller.submit(f.intent());
      expect(api.updates, 0);
      expect(controller.state.storageBlocked, isTrue);
      expect(
        controller.state.message,
        isNot(contains('PRIVATE_STORAGE_CANARY')),
      );
    });
  }
  for (final failure in ['timeout', 'wrong_receipt', 'resolution']) {
    test('$failure retains uncertainty and never resubmits', () async {
      if (failure == 'resolution') store.failResolve = true;
      api.onUpdate = (i) async {
        if (failure == 'timeout') {
          throw TimeoutException('PRIVATE_NETWORK_CANARY');
        }
        return AdminSettingsReceipt.parse({
          ...f.receiptJson(i),
          if (failure == 'wrong_receipt')
            'request_id': '99850000-0000-4000-8000-000000000002',
        });
      };
      await controller.submit(f.intent());
      await controller.submit(
        f.intent(id: '99850000-0000-4000-8000-000000000003'),
      );
      expect(api.updates, 1);
      expect(controller.state.pending.single.requestId, f.request);
      expect(
        controller.state.message,
        isNot(contains('PRIVATE_NETWORK_CANARY')),
      );
    });
  }
  test(
    'fresh not_recorded before deadline and in_progress never settle or replay',
    () async {
      api.onUpdate = (_) async => throw TimeoutException('unknown');
      await controller.submit(f.intent());
      final original = controller.state.pending.single;
      for (final status in ['not_recorded', 'in_progress']) {
        api.onLookup = (b) async =>
            AdminSettingsLookup.parse(f.lookupJson(b, now, status: status), b);
        await controller.reconcile(original);
        expect(controller.state.pending.single.requestId, f.request);
      }
      expect(api.updates, 1);
      expect(api.lookups, 2);
      expect(store.resolutions, isEmpty);
    },
  );
  test(
    'fresh absent-after-original-deadline closes uncertainty through lookup alone',
    () async {
      api.onUpdate = (_) async => throw TimeoutException('unknown');
      await controller.submit(f.intent());
      final original = controller.state.pending.single;
      now = original.expiresAt;
      api.onLookup = (b) async => AdminSettingsLookup.parse(
        f.lookupJson(b, now, status: 'not_recorded'),
        b,
      );
      await controller.reconcile(original);
      expect(controller.state.pending, isEmpty);
      expect(store.resolutions[f.request], 'not_recorded_after_deadline');
      expect(api.updates, 1);
    },
  );
  test(
    'same actor reauthenticated controller recovers original without prepared patch replay',
    () async {
      api.onUpdate = (_) async => throw TimeoutException('unknown');
      await controller.submit(f.intent());
      controller.dispose();
      session = (key: (userId: f.actor, sessionId: f.sessionB), generation: 2);
      controller = create();
      final original = controller.state.pending.single;
      await controller.reconcile(original);
      expect(api.updates, 1);
      expect(api.lookups, 1);
      expect(controller.state.pending, isEmpty);
    },
  );
  test(
    'session/access/deadline changes during durable admission deny mutation after await',
    () async {
      store.onWrite = () => session = (key: f.scope.key, generation: 2);
      await controller.submit(f.intent());
      expect(api.updates, 0);
      expect(store.resolutions[f.request], 'never_submitted');
    },
  );
  test(
    'late acknowledgment after sticky session departure cannot publish receipt or settle original',
    () async {
      final held = Completer<AdminSettingsReceipt>();
      api.onUpdate = (_) => held.future;
      final running = controller.submit(f.intent());
      await Future<void>.delayed(Duration.zero);
      current = false;
      held.complete(AdminSettingsReceipt.parse(f.receiptJson(f.intent())));
      await running;
      expect(controller.state.receipt, isNull);
      expect(store.resolutions, isEmpty);
      expect(store.read(owner).length, 1);
    },
  );
  test(
    'two controllers sharing storage cannot admit around an unknown original',
    () async {
      final other = create();
      addTearDown(other.dispose);
      api.onUpdate = (_) async => throw TimeoutException('unknown');
      await controller.submit(f.intent());
      await other.submit(f.intent(id: '99850000-0000-4000-8000-000000000003'));
      expect(api.updates, 1);
      expect(other.state.pending.single.requestId, f.request);
      expect(store.originals.length, 1);
    },
  );
  test(
    'simultaneous controllers serialize actor admission before HTTP',
    () async {
      final other = create();
      addTearDown(other.dispose);
      api.onUpdate = (_) async => throw TimeoutException('unknown');
      await Future.wait([
        controller.submit(f.intent()),
        other.submit(f.intent(id: '99850000-0000-4000-8000-000000000003')),
      ]);
      expect(api.updates, 1);
      expect(store.originals.length, 1);
    },
  );
  test(
    'denied lookup and stale sample retain durable original without exposing errors',
    () async {
      api.onUpdate = (_) async => throw TimeoutException('unknown');
      await controller.submit(f.intent());
      final original = controller.state.pending.single;
      api.onLookup = (_) async => throw StateError('PRIVATE_AUTH_CANARY');
      await controller.reconcile(original);
      expect(controller.state.pending.length, 1);
      expect(controller.state.message, isNot(contains('PRIVATE_AUTH_CANARY')));
      api.onLookup = (b) async => AdminSettingsLookup.parse(
        f.lookupJson(
          b,
          now.subtract(const Duration(minutes: 2)),
          status: 'not_recorded',
        ),
        b,
      );
      await controller.reconcile(original);
      expect(controller.state.pending.length, 1);
      expect(store.resolutions, isEmpty);
    },
  );
}
