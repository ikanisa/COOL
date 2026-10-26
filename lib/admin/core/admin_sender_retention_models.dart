import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/data/exact_json_values.dart';
import 'admin_receipt_cancel_models.dart';

Never retentionInvalid() =>
    throw const FormatException('Retention controls could not be validated.');
String retentionHash(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    retentionInvalid();
  }
  return value;
}

// Contract v1 configures the exact shipping700 lossless maintenance protocol.
// Changing that producer requires a newly admitted consumer contract.
const _retentionProtocolV1 =
    'c653c5b4ebfa6dfaea114d3f47cd2cd4efa2581c20c82e28a27c318cf35d3cf3';
void _retentionProtocol(Object? value) {
  if (retentionHash(value) != _retentionProtocolV1) retentionInvalid();
}

String retentionUtc(DateTime value) =>
    '${value.toUtc().toIso8601String().split('.').first}.${value.millisecond.toString().padLeft(3, '0')}${value.microsecond.toString().padLeft(3, '0')}Z';
String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
int _int(Object? v, int min, int max) =>
    exactJsonInteger(v, field: 'retention integer', minimum: min, maximum: max);
Map<String, dynamic> _object(Object? v, Set<String> keys) =>
    cancelObject(v, keys);
Map<String, dynamic> _freeze(Map<String, dynamic> value) => Map.unmodifiable(
  value.map(
    (key, value) =>
        MapEntry(key, value is Map<String, dynamic> ? _freeze(value) : value),
  ),
);
const _configurationKeys = {
  'revision',
  'enabled',
  'batch_limit',
  'byte_limit',
  'updated_at',
};
Map<String, dynamic> _configuration(Object? value) {
  final c = _object(value, _configurationKeys);
  c['revision'] = _int(c['revision'], 1, 1000000000);
  c['batch_limit'] = _int(c['batch_limit'], 1, 25);
  c['byte_limit'] = _int(c['byte_limit'], 1, 4194304);
  if (c['enabled'] is! bool) retentionInvalid();
  cancelInstant(c['updated_at']);
  return c;
}

Map<String, dynamic> _cron(Object? value) {
  final c = _object(value, {'state', 'job_id', 'schedule', 'command_sha256'});
  if ({'absent', 'unavailable'}.contains(c['state'])) {
    if (c['job_id'] != null ||
        c['schedule'] != null ||
        c['command_sha256'] != null) {
      retentionInvalid();
    }
  } else {
    if (!{'active', 'inactive'}.contains(c['state']) ||
        c['schedule'] != '* * * * *' ||
        c['command_sha256'] !=
            _digest('select collect_receipt_worker_history.run_schedule();')) {
      retentionInvalid();
    }
    c['job_id'] = _int(c['job_id'], 1, 9007199254740991);
  }
  return c;
}

class AdminRetentionSnapshot {
  AdminRetentionSnapshot._(this.row);
  final Map<String, dynamic> row;
  Map<String, dynamic> get configuration =>
      row['configuration'] as Map<String, dynamic>;
  Map<String, dynamic> get cron => row['cron'] as Map<String, dynamic>;
  Map<String, dynamic> get policies =>
      row['platform_policies'] as Map<String, dynamic>;
  int get revision => configuration['revision'] as int;
  bool get mutationAllowed => row['mutation_allowed'] as bool;
  String get protocolHash =>
      (row['retention'] as Map)['protocol_sha256'] as String;
  DateTime get checkedAt => cancelInstant(row['checked_at']);
  DateTime get validUntil => cancelInstant(row['sample_valid_until']);
  bool fresh(DateTime now) =>
      !now.toUtc().isBefore(checkedAt) && now.toUtc().isBefore(validUntil);
  factory AdminRetentionSnapshot.parse(
    Object? raw,
    String actor,
    String session,
  ) {
    final r = _object(raw, {
      'contract_version',
      'scope',
      'actor_id',
      'session_id',
      'checked_at',
      'sample_valid_until',
      'configuration',
      'cron',
      'retention',
      'platform_policies',
      'mutation_allowed',
    });
    if (r['contract_version'] is! int ||
        r['contract_version'] != 1 ||
        r['scope'] != 'rw_receipt_retention_controls' ||
        r['actor_id'] != cancelUuid(actor) ||
        r['session_id'] != cancelUuid(session) ||
        r['mutation_allowed'] is! bool) {
      retentionInvalid();
    }
    if (cancelInstant(
          r['sample_valid_until'],
        ).difference(cancelInstant(r['checked_at'])) !=
        const Duration(seconds: 60)) {
      retentionInvalid();
    }
    r['configuration'] = _configuration(r['configuration']);
    r['cron'] = _cron(r['cron']);
    final retention = _object(r['retention'], {
      'cold_expiry_allowed',
      'raw_financial_expiry_allowed',
      'unknown_outcome_hold_required',
      'late_callback_bindings_retained',
      'protocol_sha256',
    });
    if (retention['cold_expiry_allowed'] != false ||
        retention['raw_financial_expiry_allowed'] != false ||
        retention['unknown_outcome_hold_required'] != true ||
        retention['late_callback_bindings_retained'] != true) {
      retentionInvalid();
    }
    _retentionProtocol(retention['protocol_sha256']);
    r['retention'] = retention;
    final policies = _object(r['platform_policies'], {'scheduler', 'android'});
    for (final key in policies.keys) {
      final p = _object(policies[key], {
        'specification_sha256',
        'verification_state',
        'observed_at',
      });
      if (!{
            'release_declared',
            'unavailable',
          }.contains(p['verification_state']) ||
          p['observed_at'] != null) {
        retentionInvalid();
      }
      if (p['verification_state'] == 'release_declared') {
        retentionHash(p['specification_sha256']);
      } else if (p['specification_sha256'] != null) {
        retentionInvalid();
      }
      policies[key] = p;
    }
    r['platform_policies'] = policies;
    return AdminRetentionSnapshot._(_freeze(r));
  }
}

const _intentKeys = {
  'request_id',
  'actor_id',
  'session_id',
  'expected_revision',
  'enabled',
  'batch_limit',
  'byte_limit',
  'reason',
  'expires_at',
  'protocol_sha256',
};

class AdminRetentionIntent {
  AdminRetentionIntent._(this.row);
  final Map<String, dynamic> row;
  String get requestId => row['request_id'] as String;
  String get actorId => row['actor_id'] as String;
  String get sessionId => row['session_id'] as String;
  DateTime get expiresAt => cancelInstant(row['expires_at']);
  String get fingerprint => _digest(
    [
      'receipt-retention-v1',
      requestId,
      actorId,
      sessionId,
      row['expected_revision'].toString(),
      row['enabled'].toString(),
      row['batch_limit'].toString(),
      row['byte_limit'].toString(),
      _digest(row['reason'] as String),
      row['expires_at'],
      row['protocol_sha256'],
    ].join('\n'),
  );
  Map<String, dynamic> get parameters => Map.unmodifiable({
    'p_request_id': requestId,
    'p_expected_revision': row['expected_revision'],
    'p_enabled': row['enabled'],
    'p_batch_limit': row['batch_limit'],
    'p_byte_limit': row['byte_limit'],
    'p_reason': row['reason'],
    'p_expires_at': row['expires_at'],
  });
  factory AdminRetentionIntent.parse(Object? raw) {
    final r = _object(raw, _intentKeys);
    for (final key in ['request_id', 'actor_id', 'session_id']) {
      if (cancelUuid(r[key]) == '00000000-0000-0000-0000-000000000000') {
        retentionInvalid();
      }
    }
    r['expected_revision'] = _int(r['expected_revision'], 1, 999999999);
    r['batch_limit'] = _int(r['batch_limit'], 1, 25);
    r['byte_limit'] = _int(r['byte_limit'], 1, 4194304);
    _retentionProtocol(r['protocol_sha256']);
    cancelInstant(r['expires_at']);
    final reason = r['reason'];
    if (r['enabled'] is! bool ||
        reason is! String ||
        reason.runes.length < 10 ||
        reason.runes.length > 500 ||
        reason != reason.trim() ||
        RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(reason)) {
      retentionInvalid();
    }
    return AdminRetentionIntent._(_freeze(r));
  }
  factory AdminRetentionIntent.create({
    required AdminRetentionSnapshot snapshot,
    required String requestId,
    required bool enabled,
    required int batchLimit,
    required int byteLimit,
    required String reason,
    required DateTime now,
  }) {
    if (!snapshot.fresh(now) || !snapshot.mutationAllowed) retentionInvalid();
    return AdminRetentionIntent.parse({
      'request_id': requestId,
      'actor_id': snapshot.row['actor_id'],
      'session_id': snapshot.row['session_id'],
      'expected_revision': snapshot.revision,
      'enabled': enabled,
      'batch_limit': batchLimit,
      'byte_limit': byteLimit,
      'reason': reason,
      'expires_at': retentionUtc(now.toUtc().add(const Duration(seconds: 100))),
      'protocol_sha256': snapshot.protocolHash,
    });
  }
}

class AdminRetentionRequest {
  AdminRetentionRequest._(this.row);
  final Map<String, dynamic> row;
  bool get recorded => row['status'] == 'recorded';
  DateTime? get checkedAt => recorded ? null : cancelInstant(row['checked_at']);
  factory AdminRetentionRequest.parse(
    Object? raw,
    AdminRetentionIntent intent,
  ) {
    final r = _object(raw, {
      'contract_version',
      'scope',
      'status',
      'request_id',
      'actor_id',
      'session_id',
      'fingerprint_sha256',
      'intent',
      'recorded_at',
      'before_configuration',
      'after_configuration',
      'before_cron',
      'after_cron',
      if (raw is Map && raw['status'] == 'not_recorded') 'checked_at',
    });
    if (r['contract_version'] is! int ||
        r['contract_version'] != 1 ||
        r['scope'] != 'rw_receipt_retention_control_request' ||
        r['request_id'] != intent.requestId ||
        r['actor_id'] != intent.actorId ||
        r['session_id'] != intent.sessionId ||
        r['fingerprint_sha256'] != intent.fingerprint) {
      retentionInvalid();
    }
    if (r['status'] == 'not_recorded') {
      cancelInstant(r['checked_at']);
      if ([
        'intent',
        'recorded_at',
        'before_configuration',
        'after_configuration',
        'before_cron',
        'after_cron',
      ].any((key) => r[key] != null)) {
        retentionInvalid();
      }
    } else {
      if (r['status'] != 'recorded') retentionInvalid();
      final i = AdminRetentionIntent.parse(r['intent']);
      if (i.fingerprint != intent.fingerprint) retentionInvalid();
      final at = cancelInstant(r['recorded_at']);
      if (!at.isBefore(intent.expiresAt)) retentionInvalid();
      final before = _configuration(r['before_configuration']),
          after = _configuration(r['after_configuration']);
      if (before['revision'] != intent.row['expected_revision'] ||
          after['revision'] != before['revision'] + 1 ||
          [
            'enabled',
            'batch_limit',
            'byte_limit',
          ].any((key) => after[key] != intent.row[key]) ||
          cancelInstant(after['updated_at']).isAfter(at)) {
        retentionInvalid();
      }
      r['before_configuration'] = before;
      r['after_configuration'] = after;
      r['before_cron'] = _cron(r['before_cron']);
      r['after_cron'] = _cron(r['after_cron']);
      if ((r['after_cron'] as Map)['state'] !=
          ((intent.row['enabled'] as bool) ? 'active' : 'inactive')) {
        retentionInvalid();
      }
      r['intent'] = i.row;
    }
    return AdminRetentionRequest._(_freeze(r));
  }
}
