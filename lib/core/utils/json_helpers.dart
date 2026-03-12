/// Shared JSON / dynamic-value helpers used across repositories and services.
///
/// These functions safely coerce untyped values coming from Supabase responses
/// (which are `Map<String, dynamic>` / `List<dynamic>`) into strongly-typed
/// Dart primitives.
library;

/// Coerce a dynamic value to `Map<String, dynamic>`.
///
/// Throws [StateError] if [value] is not a [Map].
Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw StateError('Expected a JSON object but received ${value.runtimeType}.');
}

/// Returns [value] as a `Map<String, dynamic>`, or `null` if it is not a map.
Map<String, dynamic>? asMapOrNull(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

/// Returns [value] as a `Map<String, dynamic>`, or an empty map if it is not.
Map<String, dynamic> asMapOrEmpty(dynamic value) {
  return asMapOrNull(value) ?? const <String, dynamic>{};
}

/// Coerce a dynamic value to `List<Map<String, dynamic>>`.
///
/// Throws [StateError] if [value] is not a [List].
List<Map<String, dynamic>> asListOfMaps(dynamic value) {
  if (value is! List) {
    throw StateError(
      'Expected a JSON array but received ${value.runtimeType}.',
    );
  }

  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

/// Safely cast a dynamic value to [bool]. Returns `false` for `null`.
bool asBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
  return false;
}

/// Safely cast a dynamic value to [double]. Returns `null` for `null`.
double? asDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

/// Safely cast a dynamic value to [int]. Returns `null` for `null`.
int? asInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

/// Safely cast a dynamic value to [String]. Returns `null` for `null`.
String? asStringOrNull(dynamic value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}

/// Safely parse an ISO-8601 date string. Returns `null` for `null` or invalid.
DateTime? parseDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
