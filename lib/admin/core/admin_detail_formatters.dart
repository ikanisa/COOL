part of 'admin_runtime.dart';

class _AdminDetailFieldValue {
  const _AdminDetailFieldValue({required this.label, required this.value});

  final String label;
  final String value;
}

List<_AdminDetailFieldValue> _adminDetailFields(
  _AdminDetailSpec spec,
  Map<String, dynamic> data,
) {
  final usedKeys = <String>{};
  final fields = <_AdminDetailFieldValue>[];
  for (final field in spec.fields) {
    final value = _detailValue(data, field.keys, usedKeys: usedKeys);
    if (value.isNotEmpty) {
      fields.add(
        _AdminDetailFieldValue(
          label: field.label,
          value: _formatDetailFieldValue(field.label, value),
        ),
      );
    }
  }
  return fields;
}

String _formatDetailFieldValue(String label, String value) {
  if (label == 'Reference') {
    return adminCompactTransactionReference(value);
  }
  final count = int.tryParse(value);
  if (count == null) return value;
  return switch (label) {
    'Members' => '$count ${count == 1 ? 'member' : 'members'}',
    'Groups' => '$count ${count == 1 ? 'group' : 'groups'}',
    'Attempts' => '$count ${count == 1 ? 'retry' : 'retries'} available',
    'Bank evidence' => '$count pending',
    'Reconciliation exceptions' => '$count open',
    'Allocation approvals' => '$count pending',
    'Queued notifications' => '$count queued',
    'Processing notifications' => '$count processing',
    'Failed notifications' => '$count failed',
    _ => value,
  };
}

String _detailValue(
  Map<String, dynamic> data,
  List<String> keys, {
  Set<String>? usedKeys,
}) {
  for (final key in keys) {
    if (!_isSafeDetailKey(key)) continue;
    if (!data.containsKey(key)) continue;
    final value = _formatDetailValue(data[key]);
    if (value.isEmpty) continue;
    usedKeys?.add(key);
    return value;
  }
  return '';
}

String _formatDetailValue(Object? value) {
  if (value == null) return '';
  if (value is DateTime) return _formatDetailDate(value);
  if (value is num) return value.toString();
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is List) {
    return value.map(_formatDetailValue).where((v) => v.isNotEmpty).join(', ');
  }
  if (value is Map) return '';
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  final date = DateTime.tryParse(text);
  if (date != null && (text.contains('T') || text.endsWith('Z'))) {
    return _formatDetailDate(date.toLocal(), includeTime: true);
  }
  return switch (text.toLowerCase()) {
    'mtn_momo' => 'MTN MoMo',
    'airtel_money' => 'Airtel Money',
    'public_approved' => 'Public',
    'private' => 'Private',
    'provider_unavailable' => 'Provider unavailable',
    _ when text.contains('_') => _humanizeDetailValue(text),
    _ => text,
  };
}

bool _isSafeDetailKey(String key) {
  final normalized = key.toLowerCase();
  return normalized != 'available_roles' &&
      !normalized.contains('raw') &&
      !normalized.contains('secret') &&
      !normalized.contains('token') &&
      !normalized.contains('hash') &&
      !normalized.contains('body') &&
      !normalized.contains('pin');
}

String _formatDetailDate(DateTime value, {bool includeTime = false}) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${value.day} ${months[value.month - 1]} ${value.year}';
  if (!includeTime) return date;
  final time =
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}

String _humanizeDetailValue(String value) {
  final text = value.replaceAll('_', ' ').trim();
  if (text.isEmpty) return '';
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

String _adminDetailHeading(
  String rpcName,
  String pageTitle,
  String fallback,
  Map<String, dynamic> data,
) {
  String first(List<String> keys) {
    for (final key in keys) {
      final value = _formatDetailValue(data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  return switch (rpcName) {
    'admin_get_collection' => first(const ['name', 'title']),
    'admin_get_user' => first(const ['phone_masked', 'phone']),
    'admin_get_notification' => first(const ['title', 'type']),
    'admin_get_admin_user' => first(const ['phone_masked', 'public_id']),
    'admin_get_collect_transaction' => adminCompactTransactionReference(
      first(const ['reference']),
    ),
    'admin_system_health' => 'Current health',
    _ => fallback.isNotEmpty ? fallback : pageTitle,
  };
}
