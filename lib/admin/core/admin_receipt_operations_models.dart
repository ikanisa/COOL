import '../../core/data/exact_json_values.dart';
import 'admin_models.dart';

Never operationsInvalid() => throw const FormatException(
  'The receipt operations response could not be validated.',
);

Map<Object?, Object?> operationsObject(Object? raw, Set<String> keys) {
  if (raw is! Map ||
      raw.length != keys.length ||
      raw.keys.any((key) => key is! String || !keys.contains(key))) {
    operationsInvalid();
  }
  return raw;
}

String operationsUuid(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(raw)) {
    operationsInvalid();
  }
  return raw;
}

DateTime operationsInstant(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$').hasMatch(raw)) {
    operationsInvalid();
  }
  return exactJsonTimestamp(raw, field: 'receipt operations timestamp');
}

String operationsUtc(DateTime value) {
  final text = value.toUtc().toIso8601String();
  return '${text.substring(0, 20)}${text.substring(20, text.length - 1).padRight(6, '0')}Z';
}

int _operationsInt(Object? raw, int min, int max) {
  if (raw is! int || raw < min || raw > max) operationsInvalid();
  return raw;
}

bool _operationsBool(Object? raw) {
  if (raw is! bool) operationsInvalid();
  return raw;
}

List<String> _operationsIds(Object? raw, int maximum, {int minimum = 0}) {
  if (raw is! List || raw.length < minimum || raw.length > maximum) {
    operationsInvalid();
  }
  final ids = raw.map(operationsUuid).toList();
  if (ids.toSet().length != ids.length) operationsInvalid();
  return List.unmodifiable(ids);
}

bool adminReceiptOperationsCanManage(AdminIdentity? identity) =>
    identity != null &&
    identity.roles.contains('platform_owner') &&
    {
      'admin_users.manage',
      'notifications.manage',
      'system_health.read',
    }.every(identity.permissions.contains);

enum AdminReceiptOperationsMode {
  shadow('Shadow'),
  dryRun('Dry-run'),
  liveLimited('Live-limited'),
  live('Live'),
  paused('Paused');

  const AdminReceiptOperationsMode(this.label);
  final String label;
  static AdminReceiptOperationsMode parse(Object? raw) => values.firstWhere(
    (mode) => raw is String && raw == mode.label,
    orElse: operationsInvalid,
  );
}

class AdminReceiptOperationsCaps {
  const AdminReceiptOperationsCaps._(this.values);
  static const names = [
    'run_actions',
    'group_actions',
    'device_actions',
    'global_actions',
    'run_sms_segments',
    'group_sms_segments',
    'device_sms_segments',
    'global_sms_segments',
  ];
  final Map<String, int> values;
  factory AdminReceiptOperationsCaps.parse(Object? raw) {
    final row = operationsObject(raw, names.toSet());
    return AdminReceiptOperationsCaps._(
      Map.unmodifiable({
        for (final key in names) key: _operationsInt(row[key], 0, 1000000),
      }),
    );
  }
  Map<String, int> toJson() => Map.of(values);
}

class AdminReceiptOperationsPolicy {
  const AdminReceiptOperationsPolicy._({
    required this.revision,
    required this.mode,
    required this.emergencyStop,
    required this.principalIds,
    required this.collectionIds,
    required this.deviceIds,
    required this.caps,
    required this.catchupEnabled,
    required this.catchupHours,
    required this.updatedAt,
    required this.checkedAt,
  });
  final int revision;
  final AdminReceiptOperationsMode mode;
  final bool emergencyStop, catchupEnabled;
  final List<String> principalIds, collectionIds, deviceIds;
  final AdminReceiptOperationsCaps caps;
  final int catchupHours;
  final DateTime updatedAt, checkedAt;
  bool isFresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(checkedAt.add(const Duration(seconds: 60)));
  factory AdminReceiptOperationsPolicy.parse(Object? raw) {
    final row = operationsObject(raw, {
      'contract_version',
      'revision',
      'mode',
      'emergency_stop',
      'principal_ids',
      'collection_ids',
      'device_ids',
      'caps',
      'catchup_enabled',
      'catchup_hours',
      'updated_at',
      'checked_at',
    });
    if (row['contract_version'] is! int || row['contract_version'] != 2) {
      operationsInvalid();
    }
    final mode = AdminReceiptOperationsMode.parse(row['mode']);
    final stop = _operationsBool(row['emergency_stop']);
    final principals = _operationsIds(row['principal_ids'], 10);
    final groups = _operationsIds(row['collection_ids'], 100);
    final devices = _operationsIds(row['device_ids'], 10);
    final caps = AdminReceiptOperationsCaps.parse(row['caps']);
    final updated = operationsInstant(row['updated_at']);
    final checked = operationsInstant(row['checked_at']);
    if (updated.isAfter(checked) ||
        (mode == AdminReceiptOperationsMode.paused && !stop) ||
        (mode != AdminReceiptOperationsMode.paused &&
            (principals.isEmpty ||
                groups.isEmpty ||
                caps.values.values.any((v) => v == 0))) ||
        ({
              AdminReceiptOperationsMode.live,
              AdminReceiptOperationsMode.liveLimited,
            }.contains(mode) &&
            devices.isEmpty) ||
        (mode == AdminReceiptOperationsMode.liveLimited &&
            (caps.values['run_actions']! > 10 ||
                caps.values['run_sms_segments']! > 20))) {
      operationsInvalid();
    }
    return AdminReceiptOperationsPolicy._(
      revision: _operationsInt(row['revision'], 1, 1000000000),
      mode: mode,
      emergencyStop: stop,
      principalIds: principals,
      collectionIds: groups,
      deviceIds: devices,
      caps: caps,
      catchupEnabled: _operationsBool(row['catchup_enabled']),
      catchupHours: _operationsInt(row['catchup_hours'], 1, 168),
      updatedAt: updated,
      checkedAt: checked,
    );
  }
}

class AdminReceiptOperationsIntent {
  AdminReceiptOperationsIntent._({
    required this.action,
    required this.requestId,
    required this.expectedRevision,
    required this.createdAt,
    required this.expiresAt,
    required this.reason,
    required this.mode,
    required this.emergencyStop,
    this.principalIds = const [],
    this.collectionIds = const [],
    this.deviceIds = const [],
    this.caps,
    this.catchupEnabled = false,
    this.catchupHours = 24,
  }) {
    operationsUuid(requestId);
    _operationsInt(expectedRevision, 1, 999999999);
    operationsInstant(operationsUtc(createdAt));
    operationsInstant(operationsUtc(expiresAt));
    if (reason.trim() != reason ||
        reason.runes.length < 8 ||
        reason.runes.length > 500 ||
        !expiresAt.isAfter(createdAt) ||
        expiresAt.difference(createdAt) > const Duration(seconds: 120)) {
      operationsInvalid();
    }
  }
  final String action, requestId, reason;
  final int expectedRevision, catchupHours;
  final DateTime createdAt, expiresAt;
  final AdminReceiptOperationsMode mode;
  final bool emergencyStop, catchupEnabled;
  final List<String> principalIds, collectionIds, deviceIds;
  final AdminReceiptOperationsCaps? caps;
  factory AdminReceiptOperationsIntent.stop({
    required String requestId,
    required int expectedRevision,
    required DateTime createdAt,
    required DateTime expiresAt,
    required String reason,
  }) => AdminReceiptOperationsIntent._(
    action: 'stop',
    requestId: requestId,
    expectedRevision: expectedRevision,
    createdAt: createdAt,
    expiresAt: expiresAt,
    reason: reason.trim(),
    mode: AdminReceiptOperationsMode.paused,
    emergencyStop: true,
  );
  factory AdminReceiptOperationsIntent.configure({
    required String requestId,
    required int expectedRevision,
    required DateTime createdAt,
    required DateTime expiresAt,
    required String reason,
    required AdminReceiptOperationsMode mode,
    required bool emergencyStop,
    required List<String> principalIds,
    required List<String> collectionIds,
    required List<String> deviceIds,
    required AdminReceiptOperationsCaps caps,
    required bool catchupEnabled,
    required int catchupHours,
  }) {
    final principals = _operationsIds(principalIds, 10, minimum: 1);
    final groups = _operationsIds(collectionIds, 100, minimum: 1);
    final devices = _operationsIds(deviceIds, 10);
    if ((mode == AdminReceiptOperationsMode.paused && !emergencyStop) ||
        caps.values.values.any((value) => value == 0) ||
        ({
              AdminReceiptOperationsMode.live,
              AdminReceiptOperationsMode.liveLimited,
            }.contains(mode) &&
            devices.isEmpty) ||
        (mode == AdminReceiptOperationsMode.liveLimited &&
            (caps.values['run_actions']! > 10 ||
                caps.values['run_sms_segments']! > 20))) {
      operationsInvalid();
    }
    _operationsInt(catchupHours, 1, 168);
    return AdminReceiptOperationsIntent._(
      action: 'configure',
      requestId: requestId,
      expectedRevision: expectedRevision,
      createdAt: createdAt,
      expiresAt: expiresAt,
      reason: reason.trim(),
      mode: mode,
      emergencyStop: emergencyStop,
      principalIds: principals,
      collectionIds: groups,
      deviceIds: devices,
      caps: caps,
      catchupEnabled: catchupEnabled,
      catchupHours: catchupHours,
    );
  }
  Map<String, dynamic> get parameters => {
    'p_request_id': requestId,
    'p_expected_revision': expectedRevision,
    'p_reason': reason,
    'p_expires_at': operationsUtc(expiresAt),
    if (action == 'configure') ...{
      'p_mode': mode.label,
      'p_emergency_stop': emergencyStop,
      'p_principal_ids': principalIds,
      'p_collection_ids': collectionIds,
      'p_device_ids': deviceIds,
      'p_caps': caps!.toJson(),
      'p_catchup_enabled': catchupEnabled,
      'p_catchup_hours': catchupHours,
    },
  };
}

class AdminReceiptOperationsReceipt {
  const AdminReceiptOperationsReceipt._(
    this.requestId,
    this.revision,
    this.mode,
    this.emergencyStop,
    this.recordedAt,
    this.expiresAt,
  );
  final String requestId;
  final int revision;
  final AdminReceiptOperationsMode mode;
  final bool emergencyStop;
  final DateTime recordedAt, expiresAt;
  factory AdminReceiptOperationsReceipt.parse(Object? raw) {
    final row = operationsObject(raw, {
      'contract_version',
      'request_id',
      'revision',
      'mode',
      'emergency_stop',
      'recorded_at',
      'expires_at',
    });
    if (row['contract_version'] is! int || row['contract_version'] != 2) {
      operationsInvalid();
    }
    final mode = AdminReceiptOperationsMode.parse(row['mode']);
    final stop = _operationsBool(row['emergency_stop']);
    final recorded = operationsInstant(row['recorded_at']),
        expiry = operationsInstant(row['expires_at']);
    if (!expiry.isAfter(recorded) ||
        expiry.difference(recorded) > const Duration(seconds: 120) ||
        (mode == AdminReceiptOperationsMode.paused && !stop)) {
      operationsInvalid();
    }
    return AdminReceiptOperationsReceipt._(
      operationsUuid(row['request_id']),
      _operationsInt(row['revision'], 2, 1000000000),
      mode,
      stop,
      recorded,
      expiry,
    );
  }
  void validateIntent(AdminReceiptOperationsIntent intent) {
    if (requestId != intent.requestId ||
        revision != intent.expectedRevision + 1 ||
        mode != intent.mode ||
        emergencyStop != intent.emergencyStop ||
        expiresAt != intent.expiresAt ||
        recordedAt.isBefore(
          intent.createdAt.subtract(const Duration(seconds: 5)),
        )) {
      operationsInvalid();
    }
  }
}

class AdminReceiptOperationsLookup {
  const AdminReceiptOperationsLookup._(
    this.requestId,
    this.checkedAt,
    this.sampleValidUntil,
    this.status,
    this.expiresAt,
    this.receipt,
  );
  final String requestId, status;
  final DateTime checkedAt, sampleValidUntil;
  final DateTime? expiresAt;
  final AdminReceiptOperationsReceipt? receipt;
  bool isFresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(sampleValidUntil);
  factory AdminReceiptOperationsLookup.parse(
    Object? raw, {
    required String requestId,
  }) {
    operationsUuid(requestId);
    final row = operationsObject(raw, {
      'contract_version',
      'request_id',
      'checked_at',
      'sample_valid_until',
      'status',
      'expires_at',
      'receipt',
    });
    if (row['contract_version'] is! int ||
        row['contract_version'] != 2 ||
        operationsUuid(row['request_id']) != requestId ||
        row['status'] is! String ||
        !{'recorded', 'not_recorded', 'in_progress'}.contains(row['status'])) {
      operationsInvalid();
    }
    final checked = operationsInstant(row['checked_at']),
        valid = operationsInstant(row['sample_valid_until']);
    if (valid.difference(checked) != const Duration(seconds: 60)) {
      operationsInvalid();
    }
    final receipt = row['receipt'] == null
        ? null
        : AdminReceiptOperationsReceipt.parse(row['receipt']);
    final expiry = row['expires_at'] == null
        ? null
        : operationsInstant(row['expires_at']);
    if ((row['status'] == 'recorded') != (receipt != null) ||
        (receipt == null && expiry != null) ||
        (receipt != null &&
            (receipt.requestId != requestId ||
                receipt.expiresAt != expiry ||
                receipt.recordedAt.isAfter(checked)))) {
      operationsInvalid();
    }
    return AdminReceiptOperationsLookup._(
      requestId,
      checked,
      valid,
      row['status'] as String,
      expiry,
      receipt,
    );
  }
}
