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
      fields.add(_AdminDetailFieldValue(label: field.label, value: value));
    }
  }
  final extras = data.entries
      .where((entry) {
        return !usedKeys.contains(entry.key) && _isSafeDetailKey(entry.key);
      })
      .take(6);
  for (final entry in extras) {
    final value = _formatDetailValue(entry.value);
    if (value.isNotEmpty) {
      fields.add(
        _AdminDetailFieldValue(
          label: _labelizeDetailKey(entry.key),
          value: value,
        ),
      );
    }
  }
  return fields;
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
  return value.toString().trim();
}

String _labelizeDetailKey(String key) {
  final words = key.split('_').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return 'Field';
  final label = words.join(' ');
  return label[0].toUpperCase() + label.substring(1);
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

String _formatDetailDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
