/// The largest integer represented exactly by both Dart VM and JavaScript.
/// This is a transport bound, not a product or payment limit.
const maxExactJsonInteger = 9007199254740991;

int exactJsonInteger(
  Object? value, {
  required String field,
  int minimum = -maxExactJsonInteger,
  int maximum = maxExactJsonInteger,
  bool allowDigitString = false,
}) {
  if (allowDigitString && value is String) {
    if (!RegExp(r'^-?[0-9]+$').hasMatch(value)) {
      throw FormatException('Invalid integer field: $field');
    }
    // Compare the decimal representation before conversion. A web int.parse
    // must never round an out-of-range string into a permitted boundary value.
    final negative = value.startsWith('-');
    final digits = value
        .substring(negative ? 1 : 0)
        .replaceFirst(RegExp(r'^0+'), '');
    final canonical = digits.isEmpty ? '0' : digits;
    const bound = '9007199254740991';
    if (canonical.length > bound.length ||
        (canonical.length == bound.length && canonical.compareTo(bound) > 0)) {
      throw FormatException('Invalid integer field: $field');
    }
    value = int.parse('${negative ? '-' : ''}$canonical');
  }
  if (value is! num ||
      !value.isFinite ||
      value < minimum ||
      value > maximum ||
      value.remainder(1) != 0) {
    throw FormatException('Invalid integer field: $field');
  }
  return value.toInt();
}

String exactJsonIdentifier(Object? value, {required String field}) {
  if (value is! String ||
      value.isEmpty ||
      value.trim() != value ||
      RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
    throw FormatException('Invalid identifier field: $field');
  }
  return value;
}

final _zonedTimestamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})'
  r'(?:[.,](\d{1,6}))?([Zz]|([+-])(\d{2})(?::?(\d{2}))?)$',
);

/// Parse an explicit instant without normalizing impossible calendar dates.
/// Zoned ISO strings include PostgreSQL's +00 offset; naive strings are denied.
/// DateTime objects already identify an instant and are normalized to UTC.
DateTime exactJsonTimestamp(Object? value, {required String field}) {
  if (value is DateTime) {
    final utc = value.toUtc();
    if (utc.year < 1 || utc.year > 9999) {
      throw FormatException('Invalid timestamp field: $field');
    }
    return utc;
  }
  if (value is! String || value.length > 40) {
    throw FormatException('Invalid timestamp field: $field');
  }
  final match = _zonedTimestamp.firstMatch(value);
  if (match == null || match.end != value.length) {
    throw FormatException('Invalid timestamp field: $field');
  }
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);
  final offsetHour = int.parse(match[10] ?? '0');
  final offsetMinute = int.parse(match[11] ?? '0');
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetHour > 23 ||
      offsetMinute > 59) {
    throw FormatException('Invalid timestamp field: $field');
  }
  final calendar = DateTime.utc(year, month, day);
  if (calendar.year != year || calendar.month != month || calendar.day != day) {
    throw FormatException('Invalid timestamp field: $field');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.year < 1 ||
      parsed.year > 9999) {
    throw FormatException('Invalid timestamp field: $field');
  }
  return parsed;
}
