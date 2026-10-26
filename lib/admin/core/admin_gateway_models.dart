import 'admin_gateway_contracts.dart';

int _count(Object? value, {int minimum = 0, int maximum = 1000000000}) {
  if (value is! int || value < minimum || value > maximum) gatewayInvalid();
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) gatewayInvalid();
  return value;
}

String _choice(Object? value, Set<String> values) {
  if (value is! String || !values.contains(value)) gatewayInvalid();
  return value;
}

DateTime? _optionalTime(Object? value) =>
    value == null ? null : gatewayInstant(value);

bool _fresh(DateTime checked, DateTime until, DateTime now) =>
    !now.toUtc().isBefore(checked.subtract(const Duration(seconds: 5))) &&
    now.toUtc().isBefore(until);

class AdminGatewayHealth {
  const AdminGatewayHealth._(
    this.observationId,
    this.reportedAt,
    this.ingestedAt,
    this.validUntil,
    this.freshness,
    this.smsPermission,
    this.network,
    this.telephony,
    this.simSelected,
    this.localPause,
  );
  final String observationId, freshness, network, telephony;
  final DateTime reportedAt, ingestedAt, validUntil;
  final bool smsPermission, simSelected, localPause;
  factory AdminGatewayHealth.parse(Object? value, DateTime checkedAt) {
    final row = gatewayObject(value, {
      'observation_id',
      'reported_at',
      'ingested_at',
      'observation_valid_until',
      'freshness',
      'sms_permission',
      'network',
      'telephony',
      'sim_selected',
      'local_pause',
      'carrier_proof',
    });
    final reported = gatewayInstant(row['reported_at']);
    final ingested = gatewayInstant(row['ingested_at']);
    final until = gatewayInstant(row['observation_valid_until']);
    final expected = (reported.isBefore(ingested) ? reported : ingested).add(
      const Duration(seconds: 120),
    );
    final freshness = _choice(row['freshness'], {'fresh', 'stale'});
    if (row['carrier_proof'] != false ||
        ingested.isAfter(checkedAt) ||
        reported.isBefore(ingested.subtract(const Duration(seconds: 120))) ||
        reported.isAfter(ingested.add(const Duration(seconds: 30))) ||
        until != expected ||
        (freshness == 'fresh') != checkedAt.isBefore(until)) {
      gatewayInvalid();
    }
    return AdminGatewayHealth._(
      gatewayUuid(row['observation_id']),
      reported,
      ingested,
      until,
      freshness,
      _boolean(row['sms_permission']),
      _choice(row['network'], {
        'validated',
        'unvalidated',
        'offline',
        'unknown',
      }),
      _choice(row['telephony'], {'ready', 'unavailable', 'unknown'}),
      _boolean(row['sim_selected']),
      _boolean(row['local_pause']),
    );
  }
  bool isFresh(DateTime now) => _fresh(ingestedAt, validUntil, now);
}

class AdminGatewayPinnedIdentity {
  const AdminGatewayPinnedIdentity._(
    this.deviceId,
    this.installationId,
    this.keySha256,
    this.signingCertificateSha256,
  );
  final String deviceId, installationId, keySha256, signingCertificateSha256;
  factory AdminGatewayPinnedIdentity.parse(Object? value) {
    final row = gatewayObject(value, {
      'device_id',
      'installation_id',
      'key_sha256',
      'signing_certificate_sha256',
    });
    return AdminGatewayPinnedIdentity._(
      gatewayUuid(row['device_id']),
      gatewayUuid(row['installation_id']),
      gatewayHash(row['key_sha256']),
      gatewayHash(row['signing_certificate_sha256']),
    );
  }
  Map<String, dynamic> get enrollmentDocument => {
    'contract_version': 1,
    'device_id': deviceId,
    'installation_id': installationId,
    'key_sha256': keySha256,
    'signing_certificate_sha256': signingCertificateSha256,
  };
}

class AdminGatewayOwnerEvidence {
  const AdminGatewayOwnerEvidence._(this.action, this.receipt);
  final AdminGatewayOwnerAction action;
  final AdminGatewayActionReceipt receipt;
  factory AdminGatewayOwnerEvidence.parse(
    Object? value, {
    required String deviceId,
  }) {
    final row = gatewayObject(value, {'action', 'receipt'});
    final action = AdminGatewayOwnerAction.values.firstWhere(
      (action) => action.name == row['action'],
      orElse: gatewayInvalid,
    );
    final raw = gatewayObject(row['receipt'], {
      'device_id',
      'request_id',
      'state_at_action',
      'recorded_at',
      'replay',
    });
    final receipt = AdminGatewayActionReceipt.parse(
      raw,
      requestId: gatewayUuid(raw['request_id']),
      action: action,
      deviceId: deviceId,
    );
    if (receipt.replay) gatewayInvalid();
    return AdminGatewayOwnerEvidence._(action, receipt);
  }
}

class AdminGatewayDevice {
  const AdminGatewayDevice._(
    this.identity,
    this.state,
    this.enrolledAt,
    this.activatedAt,
    this.revokedAt,
    this.health,
    this.callbackTotal,
    this.sentCallbacks,
    this.deliveryCallbacks,
    this.lastOwnerAction,
  );
  final AdminGatewayPinnedIdentity identity;
  final AdminGatewayDeviceState state;
  final DateTime enrolledAt;
  final DateTime? activatedAt, revokedAt;
  final AdminGatewayHealth? health;
  final int callbackTotal, sentCallbacks, deliveryCallbacks;
  final AdminGatewayOwnerEvidence? lastOwnerAction;
  factory AdminGatewayDevice.parse(Object? value, DateTime checkedAt) {
    final row = gatewayObject(value, {
      'device_id',
      'installation_id',
      'key_sha256',
      'signing_certificate_sha256',
      'state',
      'enrolled_at',
      'activated_at',
      'revoked_at',
      'dispatch_authority',
      'dispatch_available',
      'health',
      'callback_observations',
      'last_owner_action',
    });
    final identity = AdminGatewayPinnedIdentity.parse({
      for (final name in [
        'device_id',
        'installation_id',
        'key_sha256',
        'signing_certificate_sha256',
      ])
        name: row[name],
    });
    final state = AdminGatewayDeviceState.values.firstWhere(
      (state) => state.name == row['state'],
      orElse: gatewayInvalid,
    );
    final enrolled = gatewayInstant(row['enrolled_at']);
    final activated = _optionalTime(row['activated_at']);
    final revoked = _optionalTime(row['revoked_at']);
    if (row['dispatch_authority'] != 'pending' ||
        row['dispatch_available'] != false ||
        enrolled.isAfter(checkedAt) ||
        (activated != null &&
            (activated.isBefore(enrolled) || activated.isAfter(checkedAt))) ||
        (revoked != null &&
            (revoked.isBefore(activated ?? enrolled) ||
                revoked.isAfter(checkedAt))) ||
        (state == AdminGatewayDeviceState.pending &&
            (activated != null || revoked != null)) ||
        (state == AdminGatewayDeviceState.active &&
            (activated == null || revoked != null)) ||
        (state == AdminGatewayDeviceState.revoked && revoked == null)) {
      gatewayInvalid();
    }
    final health = row['health'] == null
        ? null
        : AdminGatewayHealth.parse(row['health'], checkedAt);
    if (health != null && health.ingestedAt.isBefore(enrolled)) {
      gatewayInvalid();
    }
    final callbacks = gatewayObject(row['callback_observations'], {
      'total',
      'sent',
      'delivery',
    });
    final total = _count(callbacks['total']);
    final sent = _count(callbacks['sent']);
    final delivery = _count(callbacks['delivery']);
    if (total != sent + delivery) gatewayInvalid();
    final evidence = row['last_owner_action'] == null
        ? null
        : AdminGatewayOwnerEvidence.parse(
            row['last_owner_action'],
            deviceId: identity.deviceId,
          );
    if (evidence != null &&
        (evidence.receipt.recordedAt.isBefore(enrolled) ||
            evidence.receipt.recordedAt.isAfter(checkedAt))) {
      gatewayInvalid();
    }
    return AdminGatewayDevice._(
      identity,
      state,
      enrolled,
      activated,
      revoked,
      health,
      total,
      sent,
      delivery,
      evidence,
    );
  }
  AdminGatewayCursor get cursor =>
      AdminGatewayCursor(enrolledAt, identity.deviceId);
}

class AdminGatewayCursor {
  const AdminGatewayCursor(this.enrolledAt, this.deviceId);
  final DateTime enrolledAt;
  final String deviceId;
  factory AdminGatewayCursor.parse(Object? value) {
    final row = gatewayObject(value, {'enrolled_at', 'device_id'});
    return AdminGatewayCursor(
      gatewayInstant(row['enrolled_at']),
      gatewayUuid(row['device_id']),
    );
  }
  int compare(AdminGatewayCursor other) {
    final time = enrolledAt.compareTo(other.enrolledAt);
    return time == 0 ? deviceId.compareTo(other.deviceId) : time;
  }
}

class AdminGatewaySnapshot {
  const AdminGatewaySnapshot._(
    this.checkedAt,
    this.validUntil,
    this.rows,
    this.total,
    this.nextCursor,
  );
  final DateTime checkedAt, validUntil;
  final List<AdminGatewayDevice> rows;
  final int total;
  final AdminGatewayCursor? nextCursor;
  factory AdminGatewaySnapshot.parse(
    Object? value, {
    int limit = 20,
    DateTime? beforeEnrolledAt,
    String? beforeDeviceId,
  }) {
    if (limit < 1 ||
        limit > 50 ||
        (beforeEnrolledAt == null) != (beforeDeviceId == null) ||
        beforeEnrolledAt != null &&
            (beforeEnrolledAt.year < 1 || beforeEnrolledAt.year > 9999)) {
      gatewayInvalid();
    }
    final before = beforeEnrolledAt == null
        ? null
        : AdminGatewayCursor(
            beforeEnrolledAt.toUtc(),
            gatewayUuid(beforeDeviceId),
          );
    final row = gatewayObject(value, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'limit',
      'total',
      'next_cursor',
      'rows',
    });
    final checked = gatewayInstant(row['checked_at']);
    final until = gatewayInstant(row['sample_valid_until']);
    if (row['contract_version'] is! int ||
        row['contract_version'] != 1 ||
        row['scope'] != 'platform_global' ||
        _count(row['limit'], minimum: 1, maximum: 50) != limit ||
        until != checked.add(const Duration(seconds: 60)) ||
        row['rows'] is! List ||
        (row['rows'] as List).length > limit) {
      gatewayInvalid();
    }
    final devices = [
      for (final raw in row['rows'] as List)
        AdminGatewayDevice.parse(raw, checked),
    ];
    final total = _count(row['total']);
    if (total < devices.length) gatewayInvalid();
    final ids = <String>{}, installations = <String>{}, keys = <String>{};
    var previous = before;
    for (final device in devices) {
      if (!ids.add(device.identity.deviceId) ||
          !installations.add(device.identity.installationId) ||
          !keys.add(device.identity.keySha256) ||
          previous != null && device.cursor.compare(previous) >= 0) {
        gatewayInvalid();
      }
      previous = device.cursor;
    }
    final next = row['next_cursor'] == null
        ? null
        : AdminGatewayCursor.parse(row['next_cursor']);
    if (next == null && before == null && total != devices.length ||
        next != null &&
            (devices.length != limit ||
                total <= devices.length ||
                next.compare(devices.last.cursor) != 0)) {
      gatewayInvalid();
    }
    return AdminGatewaySnapshot._(
      checked,
      until,
      List.unmodifiable(devices),
      total,
      next,
    );
  }
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
}

class AdminGatewayRequestSnapshot {
  const AdminGatewayRequestSnapshot._(
    this.checkedAt,
    this.validUntil,
    this.requestId,
    this.action,
    this.receipt,
    this.identity,
  );
  final DateTime checkedAt, validUntil;
  final String requestId;
  final AdminGatewayOwnerAction? action;
  final AdminGatewayActionReceipt? receipt;
  final AdminGatewayPinnedIdentity? identity;
  bool get recorded => receipt != null;
  factory AdminGatewayRequestSnapshot.parse(
    Object? value, {
    required String requestId,
  }) {
    final row = gatewayObject(value, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'request_id',
      'outcome',
      'action',
      'receipt',
      'identity',
    });
    final checked = gatewayInstant(row['checked_at']);
    final until = gatewayInstant(row['sample_valid_until']);
    if (row['contract_version'] is! int ||
        row['contract_version'] != 1 ||
        row['scope'] != 'platform_global' ||
        row['request_id'] != gatewayUuid(requestId) ||
        until != checked.add(const Duration(seconds: 60))) {
      gatewayInvalid();
    }
    final outcome = _choice(row['outcome'], {'unknown', 'recorded'});
    if (outcome == 'unknown') {
      if (row['action'] != null ||
          row['receipt'] != null ||
          row['identity'] != null) {
        gatewayInvalid();
      }
      return AdminGatewayRequestSnapshot._(
        checked,
        until,
        requestId,
        null,
        null,
        null,
      );
    }
    final action = AdminGatewayOwnerAction.values.firstWhere(
      (action) => action.name == row['action'],
      orElse: gatewayInvalid,
    );
    final identity = AdminGatewayPinnedIdentity.parse(row['identity']);
    final receipt = AdminGatewayActionReceipt.parse(
      row['receipt'],
      requestId: requestId,
      action: action,
      deviceId: identity.deviceId,
    );
    if (receipt.replay || receipt.recordedAt.isAfter(checked)) gatewayInvalid();
    return AdminGatewayRequestSnapshot._(
      checked,
      until,
      requestId,
      action,
      receipt,
      identity,
    );
  }
  bool isFresh(DateTime now) => _fresh(checkedAt, validUntil, now);
}
