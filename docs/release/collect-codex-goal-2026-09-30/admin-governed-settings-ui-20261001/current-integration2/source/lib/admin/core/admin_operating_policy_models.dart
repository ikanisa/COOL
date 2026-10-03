import '../../core/data/exact_json_values.dart';
import 'admin_models.dart';

Never _policyInvalid() => throw const FormatException(
  'The unattended policy response could not be validated.',
);

Map<Object?, Object?> _policyObject(Object? raw, Set<String> keys) {
  if (raw is! Map ||
      raw.length != keys.length ||
      raw.keys.any((key) => key is! String || !keys.contains(key))) {
    _policyInvalid();
  }
  return raw;
}

void _policyConstants(Object? raw, Map<String, Object?> expected) {
  final value = _policyObject(raw, expected.keys.toSet());
  for (final entry in expected.entries) {
    if (value[entry.key] != entry.value) {
      _policyInvalid();
    }
  }
}

String _policyUuid(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(raw)) {
    _policyInvalid();
  }
  return raw;
}

DateTime _policyInstant(Object? raw) {
  if (raw is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$').hasMatch(raw)) {
    _policyInvalid();
  }
  final value = exactJsonTimestamp(raw, field: 'unattended policy timestamp');
  if (value.year < 1 || value.year > 9999) {
    _policyInvalid();
  }
  return value;
}

enum AdminPolicyMode {
  shadow('Shadow', true),
  dryRun('Dry-run', true),
  liveLimited('Live-limited', false),
  live('Live', false),
  paused('Paused', true);

  const AdminPolicyMode(this.label, this.preferenceAvailable);
  final String label;
  final bool preferenceAvailable;
  static AdminPolicyMode _parse(Object? raw) => values.firstWhere(
    (mode) => mode.label == raw && mode.preferenceAvailable,
    orElse: _policyInvalid,
  );
}

bool adminOperatingPolicyCanRead(AdminIdentity? identity) =>
    identity != null &&
    identity.roles.contains('platform_owner') &&
    identity.permissions.contains('notifications.read') &&
    identity.permissions.contains('system_health.read');

/// A verified future-policy preference. No mode in this contract grants
/// dispatch, financial, schedule, cap or approval authority.
class AdminOperatingPolicySnapshot {
  const AdminOperatingPolicySnapshot._({
    required this.id,
    required this.revision,
    required this.configuredMode,
    required this.effectiveMode,
    required this.emergencyStop,
    required this.checkedAt,
    required this.validUntil,
    required this.initializedAt,
    required this.updatedAt,
    required this.lastChangeRequestId,
    required this.assistedDispatch,
  });
  final String id, assistedDispatch;
  final int revision;
  final AdminPolicyMode configuredMode, effectiveMode;
  final bool emergencyStop;
  final DateTime checkedAt, validUntil, initializedAt, updatedAt;
  final String? lastChangeRequestId;

  bool isFresh(DateTime now) =>
      !now.isBefore(checkedAt) && now.isBefore(validUntil);

  factory AdminOperatingPolicySnapshot.parse(Object? raw) {
    final value = _policyObject(raw, {
      'contract_version',
      'scope',
      'checked_at',
      'sample_valid_until',
      'purpose',
      'policy_id',
      'revision',
      'configured_mode',
      'effective_mode',
      'emergency_stop',
      'initialized_at',
      'updated_at',
      'last_change_request_id',
      'modes',
      'limits',
      'schedule',
      'approvals',
      'execution',
      'boundaries',
    });
    if (value['contract_version'] is! int ||
        value['contract_version'] != 1 ||
        value['scope'] != 'platform_global' ||
        value['purpose'] != 'unattended_policy_preparation') {
      _policyInvalid();
    }
    final id = _policyUuid(value['policy_id']);
    final revision = value['revision'];
    if (revision is! int || revision < 1 || revision > 1000000000) {
      _policyInvalid();
    }
    final configured = AdminPolicyMode._parse(value['configured_mode']);
    final effective = AdminPolicyMode._parse(value['effective_mode']);
    final stop = value['emergency_stop'];
    if (stop is! bool ||
        (configured == AdminPolicyMode.paused && !stop) ||
        effective != (stop ? AdminPolicyMode.paused : configured)) {
      _policyInvalid();
    }
    final checked = _policyInstant(value['checked_at']);
    final valid = _policyInstant(value['sample_valid_until']);
    final initialized = _policyInstant(value['initialized_at']);
    final updated = _policyInstant(value['updated_at']);
    if (valid.difference(checked) != const Duration(seconds: 60) ||
        initialized.isAfter(updated) ||
        updated.isAfter(checked)) {
      _policyInvalid();
    }
    final last = value['last_change_request_id'] == null
        ? null
        : _policyUuid(value['last_change_request_id']);
    if ((revision == 1) != (last == null) ||
        (last == null &&
            (initialized != updated ||
                configured != AdminPolicyMode.paused ||
                !stop))) {
      _policyInvalid();
    }
    final modes = value['modes'];
    if (modes is! List || modes.length != AdminPolicyMode.values.length) {
      _policyInvalid();
    }
    for (var i = 0; i < modes.length; i++) {
      final mode = AdminPolicyMode.values[i];
      _policyConstants(modes[i], {
        'mode': mode.label,
        'selectable': mode.preferenceAvailable,
        'unavailable_reason': mode.preferenceAvailable
            ? null
            : 'OPERATING_POLICY_LIVE_AUTHORITY_PENDING',
      });
    }
    _policyConstants(value['limits'], {
      'run_actions': null,
      'group_actions': null,
      'device_actions': null,
      'global_actions': null,
      'run_sms': null,
      'group_sms': null,
      'device_sms': null,
      'global_sms': null,
      'enforcement': false,
      'unavailable_reason': 'OPERATING_POLICY_LIMIT_AUTHORITY_PENDING',
    });
    _policyConstants(value['schedule'], {
      'owner': null,
      'kind': null,
      'cadence_seconds': null,
      'next_run_at': null,
      'configuration_available': false,
      'unavailable_reason': 'OPERATING_POLICY_SCHEDULE_AUTHORITY_UNAVAILABLE',
    });
    _policyConstants(value['approvals'], {
      'financial': null,
      'recipient': null,
      'template': null,
      'pilot': null,
    });
    _policyConstants(value['execution'], {
      'unattended_dispatch_available': false,
      'grant_authority_pending': true,
      'unavailable_reason': 'OPERATING_POLICY_DISPATCH_AUTHORITY_PENDING',
    });
    final boundaries = _policyObject(value['boundaries'], {
      'assisted_dispatch',
      'policy_changes_assisted_dispatch',
      'policy_changes_signed_shadow_observation',
      'policy_changes_carrier_work',
    });
    final assisted = boundaries['assisted_dispatch'];
    if (assisted is! String ||
        !{'enabled', 'paused', 'unavailable'}.contains(assisted) ||
        boundaries['policy_changes_assisted_dispatch'] != false ||
        boundaries['policy_changes_signed_shadow_observation'] != false ||
        boundaries['policy_changes_carrier_work'] != false) {
      _policyInvalid();
    }
    return AdminOperatingPolicySnapshot._(
      id: id,
      revision: revision,
      configuredMode: configured,
      effectiveMode: effective,
      emergencyStop: stop,
      checkedAt: checked,
      validUntil: valid,
      initializedAt: initialized,
      updatedAt: updated,
      lastChangeRequestId: last,
      assistedDispatch: assisted,
    );
  }
}
