part of 'country_catalog.dart';

String _fallbackLocalDigits(String digits, String dialCode) {
  var normalized = digits;
  final dialDigits = dialCode.replaceFirst('+', '');
  if (normalized.startsWith(dialDigits)) {
    normalized = normalized.substring(dialDigits.length);
  }
  while (normalized.startsWith('0')) {
    normalized = normalized.substring(1);
  }
  return normalized;
}

bool _matchesPattern(String value, String? pattern) {
  if (pattern == null || pattern.trim().isEmpty) {
    return false;
  }
  return RegExp(pattern).hasMatch(value);
}

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Object>()
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

List<int> _asIntList(dynamic value) {
  if (value is List) {
    return value.map(_asIntOrNull).whereType<int>().toList(growable: false);
  }
  return const <int>[];
}

int? _asIntOrNull(dynamic value) {
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
