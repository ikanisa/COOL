import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_gateway_contracts.dart';
import 'admin_gateway_models.dart';
import 'admin_gateway_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_gateway_checkpoint_web.dart'
    as platform;

/// A same-tab recovery reference, without the enrollment public key or Auth data.
/// It cannot be converted into a mutation; recovery requires a fresh manual read.
class AdminGatewayCheckpoint {
  AdminGatewayCheckpoint({
    required String ownerDigest,
    required this.action,
    required String requestId,
    required String installationId,
    required String? deviceId,
    required String keySha256,
    required String signingCertificateSha256,
  }) : ownerDigest = gatewayHash(ownerDigest),
       requestId = gatewayUuid(requestId),
       installationId = gatewayUuid(installationId),
       deviceId = deviceId == null ? null : gatewayUuid(deviceId),
       keySha256 = gatewayHash(keySha256),
       signingCertificateSha256 = gatewayHash(signingCertificateSha256) {
    if ((action == AdminGatewayOwnerAction.enroll) != (deviceId == null)) {
      gatewayInvalid();
    }
  }

  final String ownerDigest, requestId, installationId;
  final String? deviceId;
  final String keySha256, signingCertificateSha256;
  final AdminGatewayOwnerAction action;

  String encode() => jsonEncode({
    'version': 1,
    'owner_digest': ownerDigest,
    'action': action.name,
    'request_id': requestId,
    'installation_id': installationId,
    'device_id': deviceId,
    'key_sha256': keySha256,
    'signing_certificate_sha256': signingCertificateSha256,
  });

  factory AdminGatewayCheckpoint.parse(String encoded, String ownerDigest) {
    if (encoded.length > 2048) gatewayInvalid();
    gatewayHash(ownerDigest);
    final row = gatewayObject(jsonDecode(encoded), {
      'version',
      'owner_digest',
      'action',
      'request_id',
      'installation_id',
      'device_id',
      'key_sha256',
      'signing_certificate_sha256',
    });
    if (row['version'] is! int ||
        row['version'] != 1 ||
        row['owner_digest'] != ownerDigest) {
      gatewayInvalid();
    }
    final action = AdminGatewayOwnerAction.values.firstWhere(
      (value) => value.name == row['action'],
      orElse: gatewayInvalid,
    );
    return AdminGatewayCheckpoint(
      ownerDigest: ownerDigest,
      action: action,
      requestId: gatewayUuid(row['request_id']),
      installationId: gatewayUuid(row['installation_id']),
      deviceId: row['device_id'] == null ? null : gatewayUuid(row['device_id']),
      keySha256: gatewayHash(row['key_sha256']),
      signingCertificateSha256: gatewayHash(row['signing_certificate_sha256']),
    );
  }

  bool matches(AdminGatewayRequestSnapshot result) =>
      result.recorded &&
      result.requestId == requestId &&
      result.action == action &&
      result.receipt?.requestId == requestId &&
      result.receipt?.deviceId == result.identity?.deviceId &&
      result.identity?.installationId == installationId &&
      result.identity?.keySha256 == keySha256 &&
      result.identity?.signingCertificateSha256 == signingCertificateSha256 &&
      (deviceId == null || result.identity?.deviceId == deviceId);
}

String adminGatewayOwnerDigest(String userId) =>
    sha256.convert(utf8.encode('collect-gateway-owner-v2:$userId')).toString();

abstract class AdminGatewayCheckpointStore {
  String? read(String ownerDigest);
  void write(String ownerDigest, String encoded);
  void clear(String ownerDigest);
}

AdminGatewayCheckpointStore? browserAdminGatewayCheckpointStore() =>
    platform.createGatewayCheckpointStore();

final adminGatewayCheckpointStoreProvider =
    Provider<AdminGatewayCheckpointStore?>(
      (ref) => browserAdminGatewayCheckpointStore(),
    );
