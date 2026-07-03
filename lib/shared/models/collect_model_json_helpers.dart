part of 'collect_models.dart';

List<String> _stringList(Object? value) {
  if (value is List) {
    return [
      for (final item in value)
        if (item != null && item.toString().trim().isNotEmpty)
          item.toString().trim(),
    ];
  }
  if (value is String && value.trim().isNotEmpty) return [value.trim()];
  return const [];
}

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Map<String, dynamic> _firstByKey(List<Map<String, dynamic>> rows, String key) {
  return rows.firstWhere(
    (item) => item['key'] == key,
    orElse: () => const <String, dynamic>{},
  );
}

String _nonEmpty(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

bool _collectionIsPublic(Map<String, dynamic> json) {
  final explicit =
      json['is_public'] ??
      json['public'] ??
      json['is_publicly_visible'] ??
      json['listed_publicly'];
  if (explicit is bool) return explicit;
  final visibility = (json['public_status'] ?? json['visibility'])
      ?.toString()
      .toLowerCase();
  return visibility == 'public' || visibility == 'public_approved';
}

DateTime _dateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}
