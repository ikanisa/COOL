import 'dart:convert';

import 'package:collect_app/admin/core/admin_action_contracts.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const gatewayDevice = '99750000-0000-4000-8000-000000000001';
const gatewayRequest = '99750000-0000-4000-8000-000000000002';
const gatewayInstallation = '99750000-0000-4000-8000-000000000003';
const gatewayCertificate =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

// The P-256 generator is public synthetic identity evidence, never a credential.
Map<String, dynamic> gatewayPublicIdentity() {
  const hex =
      '3059301306072a8648ce3d020106082a8648ce3d03010703420004'
      '6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296'
      '4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5';
  final bytes = [
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ];
  return {
    'contract_version': 1,
    'installation_id': gatewayInstallation,
    'public_key_spki_base64': base64Encode(bytes),
    'key_sha256': sha256.convert(bytes).toString(),
    'signing_certificate_sha256': gatewayCertificate,
  };
}

Map<String, dynamic> gatewayReceipt({
  String state = 'pending',
  bool replay = false,
}) => {
  'device_id': gatewayDevice,
  'request_id': gatewayRequest,
  'state_at_action': state,
  'recorded_at': '2026-10-01T10:00:00.000000Z',
  'replay': replay,
};

void main() {
  test(
    'enrollment reviews exact handset identity and returns matching document',
    () {
      final identity = AdminGatewayPublicIdentity.parse(
        gatewayPublicIdentity(),
      );
      final intent = AdminGatewayOwnerIntent.enroll(
        requestId: gatewayRequest,
        identity: identity,
      );
      expect(
        intent.parameters.keys,
        containsAll([
          'p_request_id',
          'p_installation_id',
          'p_public_key_spki_base64',
          'p_key_sha256',
          'p_signing_certificate_sha256',
        ]),
      );
      expect(identity.enrollmentDocument(gatewayDevice), {
        'contract_version': 1,
        'device_id': gatewayDevice,
        'installation_id': gatewayInstallation,
        'key_sha256': identity.keySha256,
        'signing_certificate_sha256': gatewayCertificate,
      });
      expect(
        () => intent.parameters['p_request_id'] = 'changed',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'invalid identity version key digest secret field or malformed UUID fails',
    () {
      for (final row in [
        {...gatewayPublicIdentity(), 'contract_version': 1.0},
        {...gatewayPublicIdentity(), 'installation_id': 'not-a-UUID'},
        {...gatewayPublicIdentity(), 'key_sha256': gatewayCertificate},
        {...gatewayPublicIdentity(), 'private_key': 'must not enter'},
        {...gatewayPublicIdentity(), 'public_key_spki_base64': 'invalid'},
      ]) {
        expect(
          () => AdminGatewayPublicIdentity.parse(row),
          throwsFormatException,
        );
      }
    },
  );

  test('receipts bind action request and target and retain replay history', () {
    for (final action in AdminGatewayOwnerAction.values) {
      final receipt = AdminGatewayActionReceipt.parse(
        gatewayReceipt(state: action.resultState.name, replay: true),
        requestId: gatewayRequest,
        action: action,
        deviceId: gatewayDevice,
      );
      expect(receipt.replay, isTrue);
      expect(receipt.stateAtAction, action.resultState);
    }
    for (final row in [
      {...gatewayReceipt(), 'request_id': gatewayInstallation},
      {...gatewayReceipt(), 'device_id': gatewayInstallation},
      {...gatewayReceipt(), 'state_at_action': 'delivered'},
      {...gatewayReceipt(), 'recorded_at': '2026-02-30T10:00:00Z'},
      {...gatewayReceipt(), 'replay': 'false'},
      {...gatewayReceipt(), 'sender_token': 'private'},
    ]) {
      expect(
        () => AdminGatewayActionReceipt.parse(
          row,
          requestId: gatewayRequest,
          action: AdminGatewayOwnerAction.enroll,
          deviceId: gatewayDevice,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'gateway actions validate exact requests and never accept loose success',
    () {
      final enroll = AdminGatewayOwnerIntent.enroll(
        requestId: gatewayRequest,
        identity: AdminGatewayPublicIdentity.parse(gatewayPublicIdentity()),
      );
      validateAdminActionReceipt(
        enroll.action.rpc,
        enroll.parameters,
        gatewayReceipt(),
      );
      for (final action in [
        AdminGatewayOwnerAction.activate,
        AdminGatewayOwnerAction.revoke,
      ]) {
        final intent = AdminGatewayOwnerIntent.change(
          action: action,
          requestId: gatewayRequest,
          deviceId: gatewayDevice,
          keySha256: gatewayPublicIdentity()['key_sha256'] as String,
          signingCertificateSha256: gatewayCertificate,
        );
        validateAdminActionReceipt(
          action.rpc,
          intent.parameters,
          gatewayReceipt(state: action.resultState.name),
        );
        expect(
          () => validateAdminActionReceipt(action.rpc, {
            ...intent.parameters,
            'p_send': true,
          }, gatewayReceipt(state: action.resultState.name)),
          throwsFormatException,
        );
      }
      expect(
        () => validateAdminActionReceipt(enroll.action.rpc, enroll.parameters, {
          'ok': true,
        }),
        throwsFormatException,
      );
    },
  );
}
