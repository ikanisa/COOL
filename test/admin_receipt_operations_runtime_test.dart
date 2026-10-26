import 'dart:async';
import 'package:collect_app/admin/core/admin_receipt_operations_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_receipt_operations_checkpoint_test.dart';
import 'support/admin_receipt_operations_fixture.dart';

void main() {
  final owner = adminReceiptOperationsOwnerDigest(operationsPrincipal);
  late MemoryOperationsStore store;
  late DateTime clock;
  late bool current;
  late List<AdminReceiptOperationsIntent> sent;
  late List<String> looked;
  late Future<Map<String, dynamic>> Function(AdminReceiptOperationsIntent)
  respond;
  late Future<Map<String, dynamic>> Function(String) read;
  late AdminReceiptOperationsController controller;
  AdminReceiptOperationsController create() => AdminReceiptOperationsController(
    ownerDigest: owner,
    store: store,
    now: () => clock,
    isCurrent: () => current,
    send: (intent) {
      sent.add(intent);
      return respond(intent);
    },
    lookup: (request) {
      looked.add(request);
      return read(request);
    },
  );
  setUp(() {
    store = MemoryOperationsStore();
    clock = operationsTime.add(const Duration(seconds: 2));
    current = true;
    sent = [];
    looked = [];
    respond = (intent) async => operationsReceipt(intent);
    read = (_) async => operationsLookup(operationsIntent(), clock);
    controller = create();
  });
  tearDown(() => controller.dispose());
  test(
    'immutable original is saved/readback before the single HTTP callback',
    () async {
      respond = (intent) async {
        expect(store.read(owner), [
          AdminReceiptOperationsCheckpoint.fromIntent(owner, intent).encode(),
        ]);
        return operationsReceipt(intent);
      };
      await controller.submit(operationsIntent());
      expect(sent.length, 1);
      expect(controller.state.pending, isEmpty);
      expect(store.originals.length, 1);
      expect(store.resolutions.length, 1);
    },
  );
  for (final stage in ['write', 'readback']) {
    test(
      'storage $stage failure performs no HTTP and keeps request identity without leaking errors',
      () async {
        if (stage == 'write') {
          store.failWrite = true;
        } else {
          store.tamperRead = true;
        }
        await controller.submit(operationsIntent());
        expect(sent, isEmpty);
        expect(controller.state.storageBlocked, isTrue);
        expect(controller.state.pending.single.requestId, operationsRequest);
        expect(
          controller.state.message,
          isNot(contains('PRIVATE_STORAGE_CANARY')),
        );
      },
    );
  }
  for (final failure in [
    'timeout',
    'malformed',
    'wrong_request',
    'wrong_revision',
    'expired_receipt',
    'resolve',
  ]) {
    test(
      '$failure retains original uncertainty and never retries automatically',
      () async {
        respond = (intent) async {
          if (failure == 'timeout') throw TimeoutException('PRIVATE_TIMEOUT');
          if (failure == 'resolve') store.failResolve = true;
          return switch (failure) {
            'malformed' => {'message': 'PRIVATE_CANARY'},
            'wrong_request' => {
              ...operationsReceipt(intent),
              'request_id': operationsStopRequest,
            },
            'wrong_revision' => {...operationsReceipt(intent), 'revision': 3},
            'expired_receipt' => {
              ...operationsReceipt(intent),
              'recorded_at': operationsUtc(intent.expiresAt),
            },
            _ => operationsReceipt(intent),
          };
        };
        await controller.submit(operationsIntent());
        await controller.submit(operationsIntent());
        expect(sent.length, 1);
        expect(controller.state.pending.single.requestId, operationsRequest);
        expect(controller.state.message, contains('unknown'));
        expect(controller.state.message, isNot(contains('PRIVATE')));
      },
    );
  }
  test(
    'restart reloads the original and blocks a replacement configure UUID',
    () async {
      respond = (_) async => throw TimeoutException('uncertain');
      await controller.submit(operationsIntent());
      controller.dispose();
      controller = create();
      await controller.submit(
        operationsIntent(requestId: operationsStopRequest),
      );
      expect(sent.length, 1);
      expect(controller.state.pending.single.requestId, operationsRequest);
    },
  );
  test(
    'one explicit distinct emergency stop is allowed while configure is unresolved',
    () async {
      respond = (_) async => throw TimeoutException('uncertain');
      await controller.submit(operationsIntent());
      await controller.submit(operationsIntent(stop: true));
      await controller.submit(
        operationsIntent(stop: true, requestId: operationsDevice),
      );
      expect(sent.map((i) => i.requestId), [
        operationsRequest,
        operationsStopRequest,
      ]);
      expect(controller.state.pending.length, 2);
      expect(controller.state.pendingStop, isTrue);
    },
  );
  test(
    'overlap does not stack another stop or configure while a request is active',
    () async {
      final held = Completer<Map<String, dynamic>>();
      respond = (_) => held.future;
      final action = controller.submit(operationsIntent());
      await controller.submit(operationsIntent(stop: true));
      expect(sent.length, 1);
      held.complete(operationsReceipt(operationsIntent()));
      await action;
    },
  );
  test('session departure after save stops the HTTP boundary', () async {
    store.onWrite = () => current = false;
    await controller.submit(operationsIntent());
    expect(sent, isEmpty);
    expect(store.originals.length, 1);
  });
  test(
    'session departure after HTTP ignores a late success and retains the durable original',
    () async {
      final held = Completer<Map<String, dynamic>>();
      respond = (_) => held.future;
      final action = controller.submit(operationsIntent());
      current = false;
      held.complete(operationsReceipt(operationsIntent()));
      await action;
      expect(store.resolutions, isEmpty);
      expect(store.originals.length, 1);
    },
  );
  test(
    'deadline rechecked after bookmark publication prevents a late HTTP call',
    () async {
      store.onWrite = () => clock = operationsIntent().expiresAt;
      await controller.submit(operationsIntent());
      expect(sent, isEmpty);
      expect(controller.state.pending.single.requestId, operationsRequest);
    },
  );
  test(
    'an expired or future-dated prepared action cannot even reserve storage',
    () async {
      clock = operationsIntent().expiresAt;
      await controller.submit(operationsIntent());
      expect(sent, isEmpty);
      expect(store.originals, isEmpty);
      clock = operationsTime.subtract(const Duration(seconds: 6));
      await controller.submit(operationsIntent());
      expect(sent, isEmpty);
      expect(store.originals, isEmpty);
    },
  );
  for (final seconds in [89, 90]) {
    test(
      'negative lookup at $seconds seconds only closes after original deadline',
      () async {
        respond = (_) async => throw TimeoutException('uncertain');
        await controller.submit(operationsIntent());
        clock = operationsTime.add(Duration(seconds: seconds));
        await controller.reconcile(controller.state.pending.single);
        expect(looked, [operationsRequest]);
        expect(sent.length, 1);
        expect(controller.state.pending.isEmpty, seconds == 90);
        expect(store.originals.length, 1);
      },
    );
  }
  for (final kind in [
    'in_progress',
    'stale',
    'future',
    'wrong_request',
    'wrong_receipt',
    'unavailable',
  ]) {
    test('$kind lookup preserves unknown without resubmission', () async {
      respond = (_) async => throw TimeoutException('uncertain');
      await controller.submit(operationsIntent());
      clock = operationsTime.add(const Duration(seconds: 130));
      read = (_) async {
        if (kind == 'unavailable') throw StateError('PRIVATE_BACKEND');
        return switch (kind) {
          'in_progress' => operationsLookup(
            operationsIntent(),
            clock,
            status: 'in_progress',
          ),
          'stale' => operationsLookup(
            operationsIntent(),
            clock.subtract(const Duration(seconds: 60)),
          ),
          'future' => operationsLookup(
            operationsIntent(),
            clock.add(const Duration(seconds: 6)),
          ),
          'wrong_request' => {
            ...operationsLookup(operationsIntent(), clock),
            'request_id': operationsStopRequest,
          },
          'wrong_receipt' => {
            ...operationsLookup(operationsIntent(), clock, status: 'recorded'),
            'receipt': {
              ...operationsReceipt(operationsIntent()),
              'revision': 3,
            },
          },
          _ => operationsLookup(operationsIntent(), clock),
        };
      };
      await controller.reconcile(controller.state.pending.single);
      expect(controller.state.pending.single.requestId, operationsRequest);
      expect(sent.length, 1);
      expect(controller.state.message, isNot(contains('PRIVATE')));
    });
  }
  test(
    'recorded original lookup closes uncertainty and archives rather than deleting its bookmark',
    () async {
      respond = (_) async => throw TimeoutException('uncertain');
      await controller.submit(operationsIntent());
      read = (_) async =>
          operationsLookup(operationsIntent(), clock, status: 'recorded');
      await controller.reconcile(controller.state.pending.single);
      expect(controller.state.pending, isEmpty);
      expect(sent.length, 1);
      expect(store.originals.length, 1);
      controller.dispose();
      controller = create();
      expect(controller.state.pending, isEmpty);
    },
  );
  test(
    'another owner bookmark cannot be reconciled or used as a request parameter',
    () async {
      final other = AdminReceiptOperationsCheckpoint.fromIntent(
        adminReceiptOperationsOwnerDigest(operationsDevice),
        operationsIntent(),
      );
      await controller.reconcile(other);
      expect(looked, isEmpty);
      expect(sent, isEmpty);
    },
  );
}
