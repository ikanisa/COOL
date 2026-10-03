import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_gateway_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> gatewayListFixture() =>
    jsonDecode(
          File(
            'contracts/collect-admin-gateway-v1.fixture.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> gatewayRequestFixture() =>
    jsonDecode(
          File(
            'contracts/collect-admin-gateway-owner-request-v1.fixture.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> gatewayCopy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
Map<String, dynamic> gatewayRow(Map<String, dynamic> value) =>
    (value['rows'] as List).single as Map<String, dynamic>;

void main() {
  test(
    'published backend-shaped fixture retains independent false and unknown observations',
    () {
      final data = AdminGatewaySnapshot.parse(gatewayListFixture());
      expect(data.rows.single.state, AdminGatewayDeviceState.active);
      final health = data.rows.single.health!;
      expect(health.smsPermission, isFalse);
      expect(health.network, 'unvalidated');
      expect(health.telephony, 'unknown');
      expect(health.simSelected, isFalse);
      expect(health.localPause, isTrue);
      expect(
        data.rows.single.lastOwnerAction!.receipt.stateAtAction,
        AdminGatewayDeviceState.active,
      );
    },
  );

  test(
    'list TTL and heartbeat expiry are separate and refresh never renews old health',
    () {
      final raw = gatewayListFixture();
      final data = AdminGatewaySnapshot.parse(raw);
      expect(
        data.isFresh(data.validUntil.subtract(const Duration(microseconds: 1))),
        isTrue,
      );
      expect(data.isFresh(data.validUntil), isFalse);
      final later = data.checkedAt.add(const Duration(seconds: 130));
      raw['checked_at'] = later.toIso8601String();
      raw['sample_valid_until'] = later
          .add(const Duration(seconds: 60))
          .toIso8601String();
      (gatewayRow(raw)['health'] as Map)['freshness'] = 'stale';
      final renewed = AdminGatewaySnapshot.parse(raw);
      expect(renewed.isFresh(later), isTrue);
      expect(renewed.rows.single.health!.isFresh(later), isFalse);
      expect(
        renewed.rows.single.health!.validUntil,
        data.rows.single.health!.validUntil,
      );
    },
  );

  for (final corruption in [
    'version',
    'scope',
    'extra',
    'dispatch',
    'carrier',
    'count',
    'sum',
    'expired_report_claim',
    'expiry',
    'future',
    'state',
    'activation',
    'receipt_request',
    'receipt_target',
    'receipt_state',
    'read_expiry',
  ]) {
    test('strict device read fails closed for $corruption', () {
      final raw = gatewayListFixture();
      final row = gatewayRow(raw);
      final health = row['health'] as Map;
      final receipt = (row['last_owner_action'] as Map)['receipt'] as Map;
      switch (corruption) {
        case 'version':
          raw['contract_version'] = 1.0;
        case 'scope':
          raw['scope'] = 'rwanda';
        case 'extra':
          row['owner_session_id'] = 'PRIVATE_CANARY';
        case 'dispatch':
          row['dispatch_available'] = true;
        case 'carrier':
          health['carrier_proof'] = true;
        case 'count':
          (row['callback_observations'] as Map)['total'] = 1000000001;
        case 'sum':
          (row['callback_observations'] as Map)['sent'] = 1;
        case 'expired_report_claim':
          health['freshness'] = 'stale';
        case 'expiry':
          health['observation_valid_until'] = '2026-10-01T00:03:00Z';
        case 'future':
          health['ingested_at'] = '2026-10-01T00:00:21Z';
        case 'state':
          row['state'] = 'online';
        case 'activation':
          row['activated_at'] = null;
        case 'receipt_request':
          receipt['request_id'] = null;
        case 'receipt_target':
          receipt['device_id'] = '99790000-0000-4000-8000-000000000099';
        case 'receipt_state':
          receipt['state_at_action'] = 'pending';
        case 'read_expiry':
          raw['sample_valid_until'] = '2026-10-01T00:02:20Z';
      }
      expect(() => AdminGatewaySnapshot.parse(raw), throwsFormatException);
    });
  }

  test(
    'no heartbeat is unknown; pending and revoked times remain distinct',
    () {
      final raw = gatewayListFixture();
      final row = gatewayRow(raw);
      row['state'] = 'pending';
      row['activated_at'] = null;
      row['health'] = null;
      row['last_owner_action'] = null;
      final pending = AdminGatewaySnapshot.parse(raw).rows.single;
      expect(pending.health, isNull);
      row['state'] = 'revoked';
      row['revoked_at'] = '2026-10-01T00:00:12Z';
      expect(AdminGatewaySnapshot.parse(raw).rows.single.revokedAt, isNotNull);
    },
  );

  test(
    'keyset cursor and complete first page enforce exact order and total',
    () {
      final raw = gatewayListFixture();
      raw['limit'] = 1;
      raw['total'] = 2;
      raw['next_cursor'] = {
        'enrolled_at': gatewayRow(raw)['enrolled_at'],
        'device_id': gatewayRow(raw)['device_id'],
      };
      final data = AdminGatewaySnapshot.parse(raw, limit: 1);
      expect(data.nextCursor!.deviceId, gatewayRow(raw)['device_id']);
      expect(
        () => AdminGatewaySnapshot.parse(
          raw,
          limit: 1,
          beforeEnrolledAt: data.nextCursor!.enrolledAt,
          beforeDeviceId: data.nextCursor!.deviceId,
        ),
        throwsFormatException,
      );
      raw['next_cursor'] = null;
      expect(
        () => AdminGatewaySnapshot.parse(raw, limit: 1),
        throwsFormatException,
      );
      raw['rows'] = [];
      expect(
        AdminGatewaySnapshot.parse(
          raw,
          limit: 1,
          beforeEnrolledAt: data.nextCursor!.enrolledAt,
          beforeDeviceId: data.nextCursor!.deviceId,
        ).total,
        2,
      );
      expect(
        () => AdminGatewaySnapshot.parse(
          raw,
          limit: 1,
          beforeEnrolledAt: data.nextCursor!.enrolledAt,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'recorded request binds immutable receipt and reconstructs public pairing only',
    () {
      final raw = gatewayRequestFixture();
      final data = AdminGatewayRequestSnapshot.parse(
        raw,
        requestId: raw['request_id'] as String,
      );
      expect(data.recorded, isTrue);
      expect(data.receipt!.replay, isFalse);
      expect(
        data.identity!.enrollmentDocument.keys,
        unorderedEquals([
          'contract_version',
          'device_id',
          'installation_id',
          'key_sha256',
          'signing_certificate_sha256',
        ]),
      );
    },
  );

  test(
    'unknown request never defaults to success and rejects leaked identity',
    () {
      final raw = gatewayRequestFixture();
      final identity = raw['identity'];
      raw['outcome'] = 'unknown';
      raw['action'] = raw['receipt'] = raw['identity'] = null;
      final data = AdminGatewayRequestSnapshot.parse(
        raw,
        requestId: raw['request_id'] as String,
      );
      expect(data.recorded, isFalse);
      raw['identity'] = identity;
      expect(
        () => AdminGatewayRequestSnapshot.parse(
          raw,
          requestId: raw['request_id'] as String,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'wrong request action target replay or extra request field is rejected',
    () {
      for (final corruption in [
        'request',
        'action',
        'target',
        'replay',
        'extra',
      ]) {
        final raw = gatewayRequestFixture();
        final requestId = raw['request_id'] as String;
        switch (corruption) {
          case 'request':
            raw['request_id'] = (raw['identity'] as Map)['device_id'];
          case 'action':
            raw['action'] = 'revoke';
          case 'target':
            (raw['identity'] as Map)['device_id'] = requestId;
          case 'replay':
            (raw['receipt'] as Map)['replay'] = true;
          case 'extra':
            raw['actor_id'] = 'PRIVATE_CANARY';
        }
        expect(
          () => AdminGatewayRequestSnapshot.parse(raw, requestId: requestId),
          throwsFormatException,
        );
      }
    },
  );
}
