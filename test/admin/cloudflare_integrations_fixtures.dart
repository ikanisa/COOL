import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:http/http.dart' as http;
import 'cloudflare_core_fixtures.dart';
import 'cloudflare_operating_repository_test.dart' show operatingRepository;

const integrationCert =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const integrationBody =
    'Synthetic member receipt: RWF 100 paid to Example Group.';
final integrationBodyHash = sha256
    .convert(utf8.encode(integrationBody))
    .toString();
final integrationPublicKey = base64Encode([
  for (var i = 0; i < _publicHex.length; i += 2)
    int.parse(_publicHex.substring(i, i + 2), radix: 16),
]);
final integrationKeyHash = sha256
    .convert(base64Decode(integrationPublicKey))
    .toString();
const _publicHex =
    '3059301306072a8648ce3d020106082a8648ce3d030107034200046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5';
Future<CloudflareAdminRepository> integrationRepository(
  Future<http.Response> Function(http.Request) respond, {
  bool staff = false,
}) => operatingRepository(
  respond,
  staff: staff,
  additionalPermissions: [
    'gateway.read',
    'email.read',
    if (!staff) ...['gateway.manage', 'email.manage'],
  ],
);
Map<String, dynamic> integrationDevice({bool detail = false}) => {
  'id': coreId,
  'label': 'Example gateway',
  'app_id': 'app.cool.mobile.gateway',
  'installation_id': coreId,
  'key_sha256': integrationKeyHash,
  'signing_certificate_sha256': integrationCert,
  'state': 'pending',
  'version': 1,
  'created_at': coreDate,
  'activated_at': null,
  'revoked_at': null,
  'last_heartbeat_at': null,
  'carrier_proof': false,
  'send_authority': false,
  if (detail) 'public_key_spki_base64': integrationPublicKey,
};
Map<String, dynamic> integrationGatewayDetail({bool manage = true}) => {
  'resource_type': 'gateway_devices',
  'resource': integrationDevice(detail: true),
  'current_actor_id': coreId,
  'can_manage': manage,
  'related': {'heartbeats': []},
  'related_truncated': false,
  'enrollment': {
    'contract_version': 1,
    'device_id': coreId,
    'installation_id': coreId,
    'key_sha256': integrationKeyHash,
    'signing_certificate_sha256': integrationCert,
  },
};
Map<String, dynamic> integrationReceipt() => {
  'id': coreId,
  'user_id': coreId,
  'body_sha256': integrationBodyHash,
  'status': 'needs_review',
  'version': 1,
  'received_at': coreDate,
  'created_at': coreDate,
  'public_id': '123456',
  'display_name': 'Example member',
  'transaction_id': null,
  'reviewed_at': null,
};
Map<String, dynamic> integrationReceiptDetail({bool manage = true}) => {
  'resource_type': 'member_receipts',
  'resource': integrationReceipt(),
  'current_actor_id': coreId,
  'can_manage': manage,
  'related': {'reviews': []},
  'related_truncated': false,
};
Map<String, dynamic> integrationContent() => {
  'submission_id': coreId,
  'raw_sender': 'EXAMPLE',
  'raw_body': integrationBody,
  'body_sha256': integrationBodyHash,
  'evidence_level': 'member_submitted',
};
Map<String, dynamic> integrationEmail() => {
  'id': coreId,
  'recipient_masked': 'e•••@example.test',
  'notification_type': 'member_notification',
  'status': 'accepted',
  'attempt_count': 1,
  'created_at': 1791100000,
  'updated_at': 1791100001,
  'accepted_at': 1791100001,
  'delivered_at': null,
};
