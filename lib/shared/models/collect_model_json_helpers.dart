import '../../core/data/exact_json_values.dart';

Map<String, dynamic> modelJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> modelJsonMaps(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

String nonEmptyModelText(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

DateTime modelJsonTimestamp(Object? value) =>
    exactJsonTimestamp(value, field: 'created_at');
