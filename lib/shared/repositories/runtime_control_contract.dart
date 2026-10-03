import '../models/collect_models.dart';
import '../../core/data/exact_json_values.dart';

const notificationPreferenceKeys = {
  'contribution_confirmations',
  'payment_reminders',
  'group_updates',
  'security_notices',
};

bool runtimeUuid(Object? value) =>
    value is String &&
    RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(value);

bool runtimeRevision(Object? value, {int minimum = 0}) =>
    value is int && value >= minimum && value <= 1000000000;

bool runtimeReceiptTimestamp(Object? value) {
  if (value is! String) return false;
  try {
    exactJsonTimestamp(value, field: 'runtime receipt timestamp');
    return true;
  } on FormatException {
    return false;
  }
}

bool exactRuntimeKeys(Map<dynamic, dynamic> row, Set<String> expected) =>
    row.length == expected.length && row.keys.toSet().containsAll(expected);

bool runtimeRevisionAck(Map<String, dynamic> row, int expectedRevision) =>
    row['contract_version'] == 2 &&
    row['contract_version'] is int &&
    row['ok'] == true &&
    runtimeRevision(expectedRevision) &&
    runtimeRevision(row['previous_revision']) &&
    runtimeRevision(row['revision'], minimum: 1) &&
    row['previous_revision'] == expectedRevision &&
    row['changed'] is bool &&
    row['revision'] == expectedRevision + (row['changed'] == true ? 1 : 0) &&
    runtimeReceiptTimestamp(row['updated_at']);

class NotificationPreferenceRead {
  const NotificationPreferenceRead(this.preferences, this.revision);
  final NotificationPreferences preferences;
  final int revision;

  factory NotificationPreferenceRead.parse(Object? value, String userId) {
    if (!runtimeUuid(userId) ||
        value is! Map ||
        !exactRuntimeKeys(value, {
          'contract_version',
          'ok',
          'user_id',
          'revision',
          'exists',
          'preferences',
        }) ||
        value['contract_version'] is! int ||
        value['contract_version'] != 2 ||
        value['ok'] != true ||
        value['user_id'] != userId ||
        !runtimeRevision(value['revision']) ||
        value['exists'] is! bool ||
        value['preferences'] is! Map) {
      throw const FormatException(
        'Notification preferences are unavailable. Refresh before saving.',
      );
    }
    final preferences = Map<String, dynamic>.from(value['preferences'] as Map);
    if (!exactRuntimeKeys(preferences, notificationPreferenceKeys) ||
        preferences.values.any((v) => v is! bool) ||
        value['exists'] == true && value['revision'] == 0 ||
        value['exists'] == false && preferences.values.any((v) => v != true)) {
      throw const FormatException(
        'Notification preferences are unavailable. Refresh before saving.',
      );
    }
    return NotificationPreferenceRead(
      NotificationPreferences.fromJson(preferences),
      value['revision'] as int,
    );
  }
}

int notificationPreferenceSaveRevision(
  Object? value, {
  required String userId,
  required int expectedRevision,
}) {
  if (!runtimeUuid(userId) || value is! Map) {
    throw const FormatException(
      'Notification preference save was not acknowledged. Refresh before retrying.',
    );
  }
  final row = Map<String, dynamic>.from(value);
  if (!exactRuntimeKeys(row, {
        'contract_version',
        'ok',
        'previous_revision',
        'revision',
        'changed',
        'updated_at',
        'user_id',
      }) ||
      row['user_id'] != userId ||
      !runtimeRevisionAck(row, expectedRevision)) {
    throw const FormatException(
      'Notification preference save was not acknowledged. Refresh before retrying.',
    );
  }
  return row['revision'] as int;
}
