import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/data/exact_json_values.dart';

Never gatewayInvalid() =>
    throw const FormatException('Gateway evidence could not be validated.');

Map<String, dynamic> gatewayObject(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.length != keys.length ||
      value.keys.any((key) => key is! String || !keys.contains(key))) {
    gatewayInvalid();
  }
  return Map<String, dynamic>.from(value);
}

String gatewayUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
      ).hasMatch(value)) {
    gatewayInvalid();
  }
  return value;
}

String gatewayHash(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    gatewayInvalid();
  }
  return value;
}

DateTime gatewayInstant(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
      ).hasMatch(value)) {
    gatewayInvalid();
  }
  return exactJsonTimestamp(value, field: 'gateway timestamp');
}

enum AdminGatewayDeviceState { pending, active, revoked }

enum AdminGatewayOwnerAction {
  enroll,
  activate,
  revoke;

  String get rpc => 'admin_${name}_gateway_device_v1';
  AdminGatewayDeviceState get resultState => switch (this) {
    enroll => AdminGatewayDeviceState.pending,
    activate => AdminGatewayDeviceState.active,
    revoke => AdminGatewayDeviceState.revoked,
  };
}

/// Public Android identity only. This is not a private key or device attestation.
class AdminGatewayPublicIdentity {
  const AdminGatewayPublicIdentity._(
    this.installationId,
    this.publicKey,
    this.keySha256,
    this.signingCertificateSha256,
  );
  final String installationId, publicKey, keySha256, signingCertificateSha256;

  factory AdminGatewayPublicIdentity.parse(Object? value) {
    final row = gatewayObject(value, {
      'contract_version',
      'installation_id',
      'public_key_spki_base64',
      'key_sha256',
      'signing_certificate_sha256',
    });
    if (row['contract_version'] is! int || row['contract_version'] != 1) {
      gatewayInvalid();
    }
    final key = row['public_key_spki_base64'];
    if (key is! String || !RegExp(r'^[A-Za-z0-9+/]{122}==$').hasMatch(key)) {
      gatewayInvalid();
    }
    final bytes = base64Decode(key);
    const prefix = [
      0x30,
      0x59,
      0x30,
      0x13,
      0x06,
      0x07,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x02,
      0x01,
      0x06,
      0x08,
      0x2a,
      0x86,
      0x48,
      0xce,
      0x3d,
      0x03,
      0x01,
      0x07,
      0x03,
      0x42,
      0x00,
      0x04,
    ];
    final hash = gatewayHash(row['key_sha256']);
    if (bytes.length != 91 ||
        base64Encode(bytes) != key ||
        List.generate(
          prefix.length,
          (index) => bytes[index] == prefix[index],
        ).contains(false) ||
        sha256.convert(bytes).toString() != hash) {
      gatewayInvalid();
    }
    return AdminGatewayPublicIdentity._(
      gatewayUuid(row['installation_id']),
      key,
      hash,
      gatewayHash(row['signing_certificate_sha256']),
    );
  }

  Map<String, dynamic> enrollmentDocument(String deviceId) => {
    'contract_version': 1,
    'device_id': gatewayUuid(deviceId),
    'installation_id': installationId,
    'key_sha256': keySha256,
    'signing_certificate_sha256': signingCertificateSha256,
  };
}

/// A single reviewed instruction. Its request ID survives an uncertain reply.
class AdminGatewayOwnerIntent {
  AdminGatewayOwnerIntent.enroll({
    required String requestId,
    required AdminGatewayPublicIdentity identity,
  }) : action = AdminGatewayOwnerAction.enroll,
       requestId = gatewayUuid(requestId),
       deviceId = null,
       keySha256 = identity.keySha256,
       signingCertificateSha256 = identity.signingCertificateSha256,
       publicIdentity = identity;
  AdminGatewayOwnerIntent.change({
    required this.action,
    required String requestId,
    required String deviceId,
    required String keySha256,
    required String signingCertificateSha256,
  }) : requestId = gatewayUuid(requestId),
       deviceId = gatewayUuid(deviceId),
       keySha256 = gatewayHash(keySha256),
       signingCertificateSha256 = gatewayHash(signingCertificateSha256),
       publicIdentity = null {
    if (action == AdminGatewayOwnerAction.enroll) gatewayInvalid();
  }
  final AdminGatewayOwnerAction action;
  final String requestId, keySha256, signingCertificateSha256;
  final String? deviceId;
  final AdminGatewayPublicIdentity? publicIdentity;
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    if (publicIdentity != null) ...{
      'p_installation_id': publicIdentity!.installationId,
      'p_public_key_spki_base64': publicIdentity!.publicKey,
      'p_key_sha256': keySha256,
      'p_signing_certificate_sha256': signingCertificateSha256,
    } else ...{
      'p_device_id': deviceId,
      'p_expected_key_sha256': keySha256,
      'p_expected_signing_certificate_sha256': signingCertificateSha256,
    },
  });
}

/// This immutable receipt is action-time evidence, never a current state.
class AdminGatewayActionReceipt {
  const AdminGatewayActionReceipt._(
    this.deviceId,
    this.requestId,
    this.stateAtAction,
    this.recordedAt,
    this.replay,
  );
  final String deviceId, requestId;
  final AdminGatewayDeviceState stateAtAction;
  final DateTime recordedAt;
  final bool replay;
  factory AdminGatewayActionReceipt.parse(
    Object? value, {
    required String requestId,
    AdminGatewayOwnerAction? action,
    String? deviceId,
  }) {
    final row = gatewayObject(value, {
      'device_id',
      'request_id',
      'state_at_action',
      'recorded_at',
      'replay',
    });
    final id = gatewayUuid(row['device_id']);
    final request = gatewayUuid(row['request_id']);
    final state = AdminGatewayDeviceState.values.firstWhere(
      (state) => state.name == row['state_at_action'],
      orElse: gatewayInvalid,
    );
    if (request != gatewayUuid(requestId) ||
        (deviceId != null && id != gatewayUuid(deviceId)) ||
        (action != null && state != action.resultState) ||
        row['replay'] is! bool) {
      gatewayInvalid();
    }
    return AdminGatewayActionReceipt._(
      id,
      request,
      state,
      gatewayInstant(row['recorded_at']),
      row['replay'] as bool,
    );
  }
}

bool adminGatewayActionReceiptMatches(
  String rpc,
  Map<String, dynamic> request,
  Map<String, dynamic> response,
) {
  try {
    final action = AdminGatewayOwnerAction.values.firstWhere(
      (action) => action.rpc == rpc,
      orElse: gatewayInvalid,
    );
    late AdminGatewayOwnerIntent intent;
    if (action == AdminGatewayOwnerAction.enroll) {
      gatewayObject(request, {
        'p_request_id',
        'p_installation_id',
        'p_public_key_spki_base64',
        'p_key_sha256',
        'p_signing_certificate_sha256',
      });
      intent = AdminGatewayOwnerIntent.enroll(
        requestId: gatewayUuid(request['p_request_id']),
        identity: AdminGatewayPublicIdentity.parse({
          'contract_version': 1,
          'installation_id': request['p_installation_id'],
          'public_key_spki_base64': request['p_public_key_spki_base64'],
          'key_sha256': request['p_key_sha256'],
          'signing_certificate_sha256': request['p_signing_certificate_sha256'],
        }),
      );
    } else {
      gatewayObject(request, {
        'p_request_id',
        'p_device_id',
        'p_expected_key_sha256',
        'p_expected_signing_certificate_sha256',
      });
      intent = AdminGatewayOwnerIntent.change(
        action: action,
        requestId: gatewayUuid(request['p_request_id']),
        deviceId: gatewayUuid(request['p_device_id']),
        keySha256: gatewayHash(request['p_expected_key_sha256']),
        signingCertificateSha256: gatewayHash(
          request['p_expected_signing_certificate_sha256'],
        ),
      );
    }
    AdminGatewayActionReceipt.parse(
      response,
      requestId: intent.requestId,
      action: action,
      deviceId: intent.deviceId,
    );
    return true;
  } on FormatException {
    return false;
  }
}
