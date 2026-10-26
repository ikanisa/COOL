@TestOn('browser')
library;

import 'dart:convert';
import 'package:collect_app/admin/core/admin_gateway_checkpoint.dart';
import 'package:collect_app/admin/core/admin_gateway_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'real same-tab browser adapter retains reviewed fingerprints after recreation and isolates owners',
    () {
      final owner = adminGatewayOwnerDigest('synthetic-browser-owner');
      final other = adminGatewayOwnerDigest('other-browser-owner');
      final first = browserAdminGatewayCheckpointStore()!;
      first.clear(owner);
      first.clear(other);
      final saved = AdminGatewayCheckpoint(
        ownerDigest: owner,
        action: AdminGatewayOwnerAction.enroll,
        requestId: '99790000-0000-4000-8000-000000000002',
        installationId: '99790000-0000-4000-8000-000000000001',
        deviceId: null,
        keySha256: 'a' * 64,
        signingCertificateSha256: 'b' * 64,
      );
      first.write(owner, saved.encode());
      final next = browserAdminGatewayCheckpointStore()!;
      expect(
        AdminGatewayCheckpoint.parse(next.read(owner)!, owner).encode(),
        saved.encode(),
      );
      expect(jsonDecode(next.read(owner)!).keys.toSet(), {
        'version',
        'owner_digest',
        'action',
        'request_id',
        'installation_id',
        'device_id',
        'key_sha256',
        'signing_certificate_sha256',
      });
      expect(next.read(other), isNull);
      next.clear(owner);
      expect(first.read(owner), isNull);
    },
  );
}
