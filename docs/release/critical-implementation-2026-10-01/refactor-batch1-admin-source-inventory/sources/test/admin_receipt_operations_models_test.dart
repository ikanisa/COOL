import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_receipt_operations_fixture.dart';

void main() {
  test(
    'actual private SQL default policy has no scope or quota and is paused',
    () {
      final p = AdminReceiptOperationsPolicy.parse(
        actualOperationsFixture('observed-policy-default'),
      );
      expect(p.mode, AdminReceiptOperationsMode.paused);
      expect(p.emergencyStop, isTrue);
      expect(p.principalIds, isEmpty);
      expect(p.caps.values.values, everyElement(0));
    },
  );
  for (final name in ['observed-owner-configure', 'observed-owner-stop']) {
    test('actual SQL $name matches the owner receipt contract', () {
      final receipt = AdminReceiptOperationsReceipt.parse(
        actualOperationsFixture(name),
      );
      expect(receipt.revision, greaterThan(1));
      expect(receipt.expiresAt.isAfter(receipt.recordedAt), isTrue);
    });
  }
  for (final name in [
    'observed-owner-lookup-recorded',
    'observed-owner-stop-lookup',
    'observed-owner-lookup-progress',
  ]) {
    test('actual SQL $name matches the lookup contract', () {
      final raw = actualOperationsFixture(name);
      final lookup = AdminReceiptOperationsLookup.parse(
        raw,
        requestId: raw['request_id'] as String,
      );
      expect(
        lookup.sampleValidUntil.difference(lookup.checkedAt),
        const Duration(seconds: 60),
      );
    });
  }
  for (final key in operationsPolicyFixture().keys) {
    test('policy refuses a missing $key instead of inventing readiness', () {
      final raw = operationsPolicyFixture()..remove(key);
      expect(
        () => AdminReceiptOperationsPolicy.parse(raw),
        throwsFormatException,
      );
    });
  }
  test(
    'exact schemas and integer types refuse extras, bool versions and double counters',
    () {
      expect(
        () => AdminReceiptOperationsPolicy.parse({
          ...operationsPolicyFixture(),
          'raw_phone': 'PRIVATE_CANARY',
        }),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptOperationsPolicy.parse({
          ...operationsPolicyFixture(),
          'contract_version': true,
        }),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptOperationsPolicy.parse({
          ...operationsPolicyFixture(),
          'revision': 1.0,
        }),
        throwsFormatException,
      );
    },
  );
  for (final name in AdminReceiptOperationsCaps.names) {
    test('cap $name enforces wire integers and bounds', () {
      final caps = operationsCaps().toJson();
      for (final invalid in [-1, 1000001, true, 1.0, '1', null]) {
        expect(
          () => AdminReceiptOperationsCaps.parse({...caps, name: invalid}),
          throwsFormatException,
        );
      }
    });
  }
  test(
    'policy sample expires at equality and excessive future skew remains unknown',
    () {
      final p = AdminReceiptOperationsPolicy.parse(operationsPolicyFixture());
      expect(
        p.isFresh(operationsTime.add(const Duration(seconds: 59))),
        isTrue,
      );
      expect(
        p.isFresh(operationsTime.add(const Duration(seconds: 60))),
        isFalse,
      );
      expect(
        p.isFresh(operationsTime.subtract(const Duration(seconds: 6))),
        isFalse,
      );
    },
  );
  test(
    'rollover dates and timestamps without canonical precision are refused',
    () {
      for (final value in [
        '2026-02-30T12:00:00.000000Z',
        '2026-10-01T12:00:00Z',
        '2026-10-01T12:00:00.000000+00:00',
      ]) {
        expect(() => operationsInstant(value), throwsFormatException);
      }
      expect(operationsUtc(operationsTime), '2026-10-01T12:00:00.000000Z');
    },
  );
  for (final mode in AdminReceiptOperationsMode.values) {
    test(
      'all actual modes serialize with scoped caller references: ${mode.label}',
      () {
        final intent = operationsIntent(mode: mode);
        expect(intent.parameters['p_mode'], mode.label);
        expect(intent.parameters.keys, isNot(contains('body')));
        expect(intent.parameters.keys, isNot(contains('destination')));
      },
    );
  }
  test('configure refuses empty, duplicate and invalid identity lists', () {
    void check(List<String> principals) => expect(
      () => AdminReceiptOperationsIntent.configure(
        requestId: operationsRequest,
        expectedRevision: 1,
        createdAt: operationsTime,
        expiresAt: operationsTime.add(const Duration(seconds: 90)),
        reason: 'Reviewed synthetic change',
        mode: AdminReceiptOperationsMode.shadow,
        emergencyStop: false,
        principalIds: principals,
        collectionIds: [operationsCollection],
        deviceIds: [],
        caps: operationsCaps(),
        catchupEnabled: false,
        catchupHours: 24,
      ),
      throwsFormatException,
    );
    check([]);
    check([operationsPrincipal, operationsPrincipal]);
    check(['arbitrary']);
  });
  test(
    'live modes require a device and limited mode respects pilot ceilings',
    () {
      for (final mode in [
        AdminReceiptOperationsMode.live,
        AdminReceiptOperationsMode.liveLimited,
      ]) {
        expect(
          () => AdminReceiptOperationsIntent.configure(
            requestId: operationsRequest,
            expectedRevision: 1,
            createdAt: operationsTime,
            expiresAt: operationsTime.add(const Duration(seconds: 90)),
            reason: 'Reviewed change',
            mode: mode,
            emergencyStop: false,
            principalIds: [operationsPrincipal],
            collectionIds: [operationsCollection],
            deviceIds: [],
            caps: operationsCaps(),
            catchupEnabled: false,
            catchupHours: 24,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => AdminReceiptOperationsIntent.configure(
          requestId: operationsRequest,
          expectedRevision: 1,
          createdAt: operationsTime,
          expiresAt: operationsTime.add(const Duration(seconds: 90)),
          reason: 'Reviewed change',
          mode: AdminReceiptOperationsMode.liveLimited,
          emergencyStop: false,
          principalIds: [operationsPrincipal],
          collectionIds: [operationsCollection],
          deviceIds: [operationsDevice],
          caps: operationsCaps(actions: 11),
          catchupEnabled: false,
          catchupHours: 24,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'stop needs no active device or allowlist and retains a bounded original deadline',
    () {
      final stop = operationsIntent(stop: true);
      expect(stop.parameters.keys.toSet(), {
        'p_request_id',
        'p_expected_revision',
        'p_reason',
        'p_expires_at',
      });
      for (final seconds in [0, 121]) {
        expect(
          () => AdminReceiptOperationsIntent.stop(
            requestId: operationsRequest,
            expectedRevision: 1,
            createdAt: operationsTime,
            expiresAt: operationsTime.add(Duration(seconds: seconds)),
            reason: 'Reviewed stop',
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'receipt is bound to exact request, next revision, mode and original deadline',
    () {
      final intent = operationsIntent(),
          raw = operationsReceipt(operationsIntent());
      AdminReceiptOperationsReceipt.parse(raw).validateIntent(intent);
      for (final field in [
        'request_id',
        'revision',
        'mode',
        'emergency_stop',
        'expires_at',
      ]) {
        final changed = {
          ...raw,
          field: switch (field) {
            'request_id' => operationsStopRequest,
            'revision' => 3,
            'mode' => 'Dry-run',
            'emergency_stop' => true,
            _ => operationsUtc(
              intent.expiresAt.add(const Duration(seconds: 1)),
            ),
          },
        };
        expect(
          () => AdminReceiptOperationsReceipt.parse(
            changed,
          ).validateIntent(intent),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'recorded timestamps cannot equal expiry or exceed the120second receipt window',
    () {
      final raw = operationsReceipt(operationsIntent());
      expect(
        () => AdminReceiptOperationsReceipt.parse({
          ...raw,
          'recorded_at': raw['expires_at'],
        }),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptOperationsReceipt.parse({
          ...raw,
          'expires_at': operationsUtc(
            operationsTime.add(const Duration(seconds: 122)),
          ),
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'lookup refuses wrong request, invented receipt, inconsistent expiry and wrong TTL',
    () {
      final intent = operationsIntent(),
          raw = operationsLookup(
            operationsIntent(),
            operationsTime.add(const Duration(seconds: 2)),
            status: 'recorded',
          );
      for (final changed in [
        {...raw, 'request_id': operationsStopRequest},
        {...raw, 'status': 'in_progress'},
        {...raw, 'expires_at': null},
        {
          ...raw,
          'sample_valid_until': operationsUtc(
            operationsTime.add(const Duration(seconds: 61)),
          ),
        },
      ]) {
        expect(
          () => AdminReceiptOperationsLookup.parse(
            changed,
            requestId: intent.requestId,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
