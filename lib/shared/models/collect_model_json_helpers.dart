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
