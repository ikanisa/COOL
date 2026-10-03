import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_gateway_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _observed(String name) =>
    jsonDecode(
          File(
            'docs/release/collect-codex-goal-2026-09-30/gateway-admin/backend-uat/observed-$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

void main() {
  for (final name in ['empty', 'pending', 'active', 'revoked-callbacks']) {
    test(
      'actual isolated SQL $name receipt passes current strict device DTO',
      () {
        final raw = _observed(name);
        final snapshot = AdminGatewaySnapshot.parse(raw);
        expect(snapshot.total, raw['total']);
        expect(snapshot.rows.length, (raw['rows'] as List).length);
        if (name == 'empty') expect(snapshot.rows, isEmpty);
        if (name == 'active') {
          final device = snapshot.rows.firstWhere(
            (row) => row.state == AdminGatewayDeviceState.active,
          );
          expect(device.health!.smsPermission, isFalse);
          expect(device.health!.telephony, 'unknown');
          expect(device.health!.localPause, isTrue);
        }
        if (name == 'revoked-callbacks') {
          final device = snapshot.rows.firstWhere(
            (row) => row.state == AdminGatewayDeviceState.revoked,
          );
          expect(device.callbackTotal, 2);
          expect(device.sentCallbacks, 1);
          expect(device.deliveryCallbacks, 1);
          expect(
            device.lastOwnerAction!.receipt.stateAtAction,
            AdminGatewayDeviceState.revoked,
          );
        }
      },
    );
  }
  test(
    'actual isolated actor-bound owner request passes immutable receipt DTO',
    () {
      final raw = _observed('owner-request');
      final snapshot = AdminGatewayRequestSnapshot.parse(
        raw,
        requestId: raw['request_id'] as String,
      );
      expect(snapshot.action, AdminGatewayOwnerAction.revoke);
      expect(snapshot.receipt!.replay, isFalse);
      expect(snapshot.receipt!.deviceId, snapshot.identity!.deviceId);
    },
  );
}
