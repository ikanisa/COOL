import '../../core/data/exact_json_values.dart';

void validateAdminMemberIdentity(Map<String, dynamic> row) {
  const keys = {
    'id',
    'collect_id',
    'member_name',
    'momo_registered_name',
    'momo_number',
    'whatsapp_phone',
    'momo_pay_code',
    'member_type',
    'contributed_amount_rwf',
    'contribution_status',
    'account_state',
    'origin',
    'lifecycle',
    'active_groups',
    'created_at',
  };
  bool text(Object? value) =>
      value is String && value.trim().isNotEmpty && value.length <= 16000;
  bool phone(Object? value) =>
      value == null ||
      value is String && RegExp(r'^\+2507[2389][0-9]{7}$').hasMatch(value);
  bool id(Object? value) =>
      value is String &&
      RegExp(r'^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(value);
  final type = row['member_type'],
      amount = row['contributed_amount_rwf'],
      code = row['momo_pay_code'];
  if (row.length != keys.length ||
      !row.keys.every(keys.contains) ||
      !id(row['id']) ||
      row['collect_id'] is! String ||
      !RegExp(r'^[0-9]{6}$').hasMatch(row['collect_id'] as String) ||
      !{'App', 'Direct'}.contains(type) ||
      !phone(row['momo_number']) ||
      !phone(row['whatsapp_phone']) ||
      type == 'Direct' && row['whatsapp_phone'] != null ||
      type == 'App' && row['whatsapp_phone'] == null ||
      code != null &&
          (code is! String || !RegExp(r'^[0-9]{4,9}$').hasMatch(code)) ||
      ![
        'member_name',
        'momo_registered_name',
      ].every((key) => row[key] == null || text(row[key])) ||
      ![
        'account_state',
        'origin',
        'lifecycle',
      ].every((key) => text(row[key])) ||
      row['active_groups'] is! int ||
      (row['active_groups'] as int) < 0 ||
      (row['active_groups'] as int) > maxExactJsonInteger ||
      !(row['contribution_status'] == 'unavailable' && amount == null ||
          row['contribution_status'] == 'available' &&
              amount is String &&
              RegExp(
                r'^-?(?:0|[1-9][0-9]{0,17})(?:\.[0-9]{1,2})?$',
              ).hasMatch(amount))) {
    throw const FormatException('Invalid member identity evidence.');
  }
  exactJsonTimestamp(row['created_at'], field: 'Member created at');
}
