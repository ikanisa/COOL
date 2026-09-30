import '../models/collect_models.dart';

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
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null) return false;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final calendar = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  return calendar.year == parts[0] &&
      calendar.month == parts[1] &&
      calendar.day == parts[2] &&
      calendar.hour == parts[3] &&
      calendar.minute == parts[4] &&
      calendar.second == parts[5] &&
      (match.group(7) == null ||
          int.parse(match.group(7)!) <= 23 &&
              int.parse(match.group(8)!) <= 59) &&
      DateTime.tryParse(value) != null;
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
