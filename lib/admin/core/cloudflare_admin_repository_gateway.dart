part of 'cloudflare_admin_repository.dart';

enum CloudflareGatewayAction { enroll, activate, revoke }

class CloudflareGatewayDevice {
  const CloudflareGatewayDevice(this.values);
  final Map<String, dynamic> values;
  String get id => values['id'] as String;
  String get label => values['label'] as String;
  String get state => values['state'] as String;
  int get version => values['version'] as int;
  factory CloudflareGatewayDevice.parse(
    Map<String, dynamic> data, {
    bool detail = false,
  }) {
    const fields = {
      'id',
      'label',
      'app_id',
      'installation_id',
      'key_sha256',
      'signing_certificate_sha256',
      'state',
      'version',
      'created_at',
      'activated_at',
      'revoked_at',
      'last_heartbeat_at',
      'carrier_proof',
      'send_authority',
    };
    final allowed = {...fields, if (detail) 'public_key_spki_base64'};
    if (data.length != allowed.length ||
        !data.keys.every(allowed.contains) ||
        !_coreId(data['id']) ||
        !_coreId(data['installation_id']) ||
        data['label'] is! String ||
        (data['label'] as String).trim().length < 2 ||
        (data['label'] as String).length > 120 ||
        data['app_id'] is! String ||
        !RegExp(
          r'^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$',
        ).hasMatch(data['app_id'] as String) ||
        (data['app_id'] as String).length > 160 ||
        !{'pending', 'active', 'revoked'}.contains(data['state']) ||
        !_coreInteger(data['version']) ||
        data['version'] == 0 ||
        !_coreTimestamp(data['created_at']) ||
        data['carrier_proof'] != false ||
        data['send_authority'] != false) {
      _invalidCore();
    }
    for (final key in ['key_sha256', 'signing_certificate_sha256']) {
      if (data[key] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(data[key] as String)) {
        _invalidCore();
      }
    }
    for (final key in ['activated_at', 'revoked_at', 'last_heartbeat_at']) {
      if (data[key] != null &&
          (!_coreTimestamp(data[key]) ||
              DateTime.parse(
                data[key] as String,
              ).isBefore(DateTime.parse(data['created_at'] as String)))) {
        _invalidCore();
      }
    }
    if ((data['state'] == 'pending' &&
            (data['activated_at'] != null || data['revoked_at'] != null)) ||
        (data['state'] == 'active' &&
            (data['activated_at'] == null || data['revoked_at'] != null)) ||
        (data['state'] == 'revoked' && data['revoked_at'] == null)) {
      _invalidCore();
    }
    if (detail &&
        !validCloudflareGatewayKey(
          data['public_key_spki_base64'],
          data['key_sha256'],
        )) {
      _invalidCore();
    }
    return CloudflareGatewayDevice(Map.unmodifiable(data));
  }
}

bool _gatewayObservationTime(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
      ).hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      parsed.toUtc().toIso8601String().substring(0, 19) ==
          value.substring(0, 19);
}

bool validCloudflareGatewayKey(Object? encoded, Object? fingerprint) {
  if (encoded is! String || fingerprint is! String || encoded.length != 124) {
    return false;
  }
  try {
    final bytes = base64Decode(encoded);
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
    return bytes.length == 91 &&
        base64Encode(bytes) == encoded &&
        List.generate(
          prefix.length,
          (i) => bytes[i] == prefix[i],
        ).every((same) => same) &&
        sha256.convert(bytes).toString() == fingerprint;
  } catch (_) {
    return false;
  }
}

class CloudflareGatewayDetail {
  const CloudflareGatewayDetail({
    required this.device,
    required this.canManage,
    required this.heartbeats,
    required this.enrollment,
    required this.truncated,
  });
  final CloudflareGatewayDevice device;
  final bool canManage;
  final List<Map<String, dynamic>> heartbeats;
  final Map<String, dynamic> enrollment;
  final bool truncated;
}

extension CloudflareGatewayRepository on CloudflareAdminRepository {
  Future<({List<CloudflareGatewayDevice> rows, int total})> gatewayDeviceList({
    String state = '',
    int offset = 0,
  }) async {
    if (!{'', 'pending', 'active', 'revoked'}.contains(state) ||
        offset < 0 ||
        offset > 2147483647) {
      throw const FormatException('Invalid device filters.');
    }
    final query = Uri(
      queryParameters: {
        'limit': '25',
        'offset': '$offset',
        if (state.isNotEmpty) 'state': state,
      },
    ).query;
    final result = await _read('gateway/devices?$query', 'gateway.read');
    if (result.length != 2 ||
        result['rows'] is! List ||
        !_coreInteger(result['total'])) {
      _invalidCore();
    }
    final rows = [
      for (final value in result['rows'] as List)
        if (value is Map)
          CloudflareGatewayDevice.parse(Map<String, dynamic>.from(value))
        else
          _invalidCore(),
    ];
    final total = result['total'] as int;
    if (rows.length > 25 ||
        rows.length != (total - offset).clamp(0, 25) ||
        rows.map((row) => row.id).toSet().length != rows.length ||
        state.isNotEmpty && rows.any((row) => row.state != state)) {
      _invalidCore();
    }
    return (rows: rows, total: total);
  }

  Future<CloudflareGatewayDetail> gatewayDevice(String id) async {
    if (!_coreId(id)) throw const FormatException('Select a valid device.');
    final result = await _read('gateway/devices/$id', 'gateway.read');
    if (result.length != 7 ||
        result['resource_type'] != 'gateway_devices' ||
        result['resource'] is! Map ||
        result['current_actor_id'] != session.user?.id ||
        result['can_manage'] is! bool ||
        result['related_truncated'] is! bool ||
        result['related'] is! Map ||
        result['enrollment'] is! Map) {
      _invalidCore();
    }
    final device = CloudflareGatewayDevice.parse(
      Map<String, dynamic>.from(result['resource'] as Map),
      detail: true,
    );
    if (device.id != id ||
        (session.user?.role == AdminAccountRole.staff &&
            result['can_manage'] != false)) {
      _invalidCore();
    }
    final related = result['related'] as Map;
    if (related.length != 1 ||
        related['heartbeats'] is! List ||
        (related['heartbeats'] as List).length > 100) {
      _invalidCore();
    }
    final heartbeats = [
      for (final row in related['heartbeats'] as List)
        if (row is Map) Map<String, dynamic>.from(row) else _invalidCore(),
    ];
    const heartbeatFields = {
      'observation_id',
      'request_id',
      'issued_at',
      'reported_at',
      'ingested_at',
      'sms_permission',
      'network',
      'telephony',
      'sim_selected',
      'sim_revision_sha256',
      'local_pause',
      'carrier_proof',
      'send_authority',
    };
    for (final row in heartbeats) {
      if (row.length != heartbeatFields.length ||
          !row.keys.every(heartbeatFields.contains) ||
          !_coreId(row['observation_id']) ||
          !_coreId(row['request_id']) ||
          ![
            'issued_at',
            'reported_at',
            'ingested_at',
          ].every((key) => _gatewayObservationTime(row[key])) ||
          ![
            'sms_permission',
            'sim_selected',
            'local_pause',
          ].every((key) => row[key] is bool) ||
          !{
            'validated',
            'unvalidated',
            'offline',
            'unknown',
          }.contains(row['network']) ||
          !{'ready', 'unavailable', 'unknown'}.contains(row['telephony']) ||
          row['carrier_proof'] != false ||
          row['send_authority'] != false ||
          (row['sim_selected'] == true
              ? row['sim_revision_sha256'] is! String ||
                    !RegExp(
                      r'^[a-f0-9]{64}$',
                    ).hasMatch(row['sim_revision_sha256'] as String)
              : row['sim_revision_sha256'] != null)) {
        _invalidCore();
      }
    }
    final enrollment = Map<String, dynamic>.from(result['enrollment'] as Map);
    if (enrollment.length != 5 ||
        enrollment['contract_version'] != 1 ||
        enrollment['device_id'] != device.id ||
        enrollment['installation_id'] != device.values['installation_id'] ||
        enrollment['key_sha256'] != device.values['key_sha256'] ||
        enrollment['signing_certificate_sha256'] !=
            device.values['signing_certificate_sha256']) {
      _invalidCore();
    }
    return CloudflareGatewayDetail(
      device: device,
      canManage: result['can_manage'] as bool,
      heartbeats: heartbeats,
      enrollment: enrollment,
      truncated: result['related_truncated'] as bool,
    );
  }

  Future<CloudflareOperationReceipt> gatewayAction(
    CloudflareGatewayAction action, {
    String? id,
    required String key,
    required Map<String, dynamic> body,
  }) async {
    final changesDevice = action != CloudflareGatewayAction.enroll;
    if (changesDevice && !_coreId(id) ||
        !changesDevice && id != null ||
        !RegExp(r'^[A-Za-z0-9_.-]{8,200}$').hasMatch(key) ||
        body['reason'] is! String ||
        (body['reason'] as String).trim().length < 8 ||
        (body['reason'] as String).trim().length > 1000 ||
        changesDevice &&
            (!_coreInteger(body['expected_version']) ||
                body['expected_version'] == 0)) {
      throw const FormatException(
        'Provide the device identity, current version and reason.',
      );
    }
    final allowed = changesDevice
        ? {
            'expected_version',
            'expected_key_sha256',
            'expected_signing_certificate_sha256',
            'reason',
          }
        : {
            'label',
            'app_id',
            'installation_id',
            'public_key_spki_base64',
            'key_sha256',
            'signing_certificate_sha256',
            'reason',
          };
    if (body.length != allowed.length || !body.keys.every(allowed.contains)) {
      throw const FormatException('Device request fields are invalid.');
    }
    if (!changesDevice &&
        !validCloudflareGatewayKey(
          body['public_key_spki_base64'],
          body['key_sha256'],
        )) {
      throw const FormatException(
        'The public key and SHA-256 fingerprint do not match.',
      );
    }
    final before = _requirePermission('gateway.manage');
    if (before.role == AdminAccountRole.staff) {
      throw const AdminAccountException(
        'Your account can view devices but cannot manage them.',
      );
    }
    final result = await session.request(
      'gateway/devices${changesDevice ? '/$id/${action.name}' : ''}',
      method: 'POST',
      body: body,
      idempotencyKey: key,
      authenticated: true,
    );
    final after = _requirePermission('gateway.manage');
    if (before.id != after.id || before.sessionId != after.sessionId) {
      throw const AdminAccountException(
        'Your session changed. Check the request reference.',
      );
    }
    final receipt = CloudflareOperationReceipt.parse(result);
    if (receipt.resourceType != 'gateway_devices' ||
        changesDevice && receipt.resourceId != id ||
        receipt.version !=
            (changesDevice ? (body['expected_version'] as int) + 1 : 1)) {
      _invalidCore();
    }
    return receipt;
  }
}
