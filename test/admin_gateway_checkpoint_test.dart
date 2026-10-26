import 'dart:convert';

import 'package:collect_app/admin/core/admin_gateway_checkpoint.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:collect_app/admin/core/admin_gateway_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'admin_gateway_contracts_test.dart' as identity;
import 'admin_gateway_models_test.dart' as source;

void main() {
  final owner = adminGatewayOwnerDigest('synthetic-owner');
  final public = identity.gatewayPublicIdentity();
  AdminGatewayCheckpoint checkpoint({
    AdminGatewayOwnerAction action = AdminGatewayOwnerAction.enroll,
  }) => AdminGatewayCheckpoint(
    ownerDigest: owner,
    action: action,
    requestId: identity.gatewayRequest,
    installationId: identity.gatewayInstallation,
    deviceId: action == AdminGatewayOwnerAction.enroll
        ? null
        : identity.gatewayDevice,
    keySha256: public['key_sha256'] as String,
    signingCertificateSha256: public['signing_certificate_sha256'] as String,
  );
  test(
    'bounded checkpoint contains only reviewed nonsensitive references, never the SPKI or replay parameters',
    () {
      final encoded = checkpoint().encode();
      final row = jsonDecode(encoded) as Map;
      expect(row.keys.toSet(), {
        'version',
        'owner_digest',
        'action',
        'request_id',
        'installation_id',
        'device_id',
        'key_sha256',
        'signing_certificate_sha256',
      });
      expect(encoded.length, lessThan(2048));
      expect(
        encoded,
        isNot(contains(public['public_key_spki_base64'] as String)),
      );
      expect(encoded, isNot(contains('p_request_id')));
      expect(AdminGatewayCheckpoint.parse(encoded, owner).encode(), encoded);
    },
  );
  test(
    'fixed project and purpose owner binding differs from another actor',
    () {
      expect(owner, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(owner, isNot(contains('synthetic-owner')));
      expect(owner, isNot(adminGatewayOwnerDigest('another-owner')));
      expect(
        () => AdminGatewayCheckpoint.parse(
          checkpoint().encode(),
          adminGatewayOwnerDigest('another-owner'),
        ),
        throwsFormatException,
      );
    },
  );
  for (final field in [
    'version',
    'owner_digest',
    'action',
    'request_id',
    'installation_id',
    'device_id',
    'key_sha256',
    'signing_certificate_sha256',
    'public_key_spki_base64',
  ]) {
    test('strict checkpoint rejects altered $field', () {
      final row = jsonDecode(checkpoint().encode()) as Map<String, dynamic>;
      row[field] = field == 'version' ? true : 'invalid';
      expect(
        () => AdminGatewayCheckpoint.parse(jsonEncode(row), owner),
        throwsFormatException,
      );
    });
  }
  test(
    'oversized bookmark and missing change-device identity are rejected',
    () {
      expect(
        () => AdminGatewayCheckpoint.parse('x' * 2049, owner),
        throwsFormatException,
      );
      expect(
        () => AdminGatewayCheckpoint(
          ownerDigest: owner,
          action: AdminGatewayOwnerAction.activate,
          requestId: identity.gatewayRequest,
          installationId: identity.gatewayInstallation,
          deviceId: null,
          keySha256: public['key_sha256'] as String,
          signingCertificateSha256:
              public['signing_certificate_sha256'] as String,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'recorded recovery binds all reviewed fingerprints and original action without recreating a mutation',
    () {
      final raw = source.gatewayRequestFixture();
      final saved = checkpoint();
      raw['request_id'] = identity.gatewayRequest;
      raw['action'] = 'enroll';
      (raw['receipt'] as Map)['request_id'] = identity.gatewayRequest;
      (raw['receipt'] as Map)['state_at_action'] = 'pending';
      (raw['identity'] as Map)['installation_id'] = saved.installationId;
      (raw['identity'] as Map)['key_sha256'] = saved.keySha256;
      (raw['identity'] as Map)['signing_certificate_sha256'] =
          saved.signingCertificateSha256;
      expect(
        saved.matches(
          AdminGatewayRequestSnapshot.parse(
            raw,
            requestId: identity.gatewayRequest,
          ),
        ),
        isTrue,
      );
      for (final field in [
        'installation_id',
        'key_sha256',
        'signing_certificate_sha256',
      ]) {
        final changed = source.gatewayCopy(raw);
        (changed['identity'] as Map)[field] = field == 'installation_id'
            ? '99790000-0000-4000-8000-000000000099'
            : 'f' * 64;
        expect(
          saved.matches(
            AdminGatewayRequestSnapshot.parse(
              changed,
              requestId: identity.gatewayRequest,
            ),
          ),
          isFalse,
        );
      }
      final unknown = source.gatewayCopy(raw)
        ..['outcome'] = 'unknown'
        ..['action'] = null
        ..['receipt'] = null
        ..['identity'] = null;
      expect(
        saved.matches(
          AdminGatewayRequestSnapshot.parse(
            unknown,
            requestId: identity.gatewayRequest,
          ),
        ),
        isFalse,
      );
    },
  );
}
