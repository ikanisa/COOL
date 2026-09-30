part of 'collect_models.dart';

// A transport precision bound shared by native and JavaScript, not a MoMo limit.
const _paymentMaxExactInteger = 9007199254740991;
final _paymentControlCharacter = RegExp(r'[\u0000-\u001F\u007F]');
final _paymentTimestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})'
  r'(?:[.,](\d{1,6}))?([Zz]|([+-])(\d{2})(?::?(\d{2}))?)$',
);

int _paymentPositiveInteger(Object? value, String field) {
  if (value is! num ||
      !value.isFinite ||
      value <= 0 ||
      value > _paymentMaxExactInteger ||
      value.remainder(1) != 0) {
    throw FormatException('Invalid payment amount: $field');
  }
  return value.toInt();
}

int _paymentAmount(
  Map<String, dynamic> json,
  String currentKey,
  String legacyKey,
) {
  final currentValue = json[currentKey];
  final legacyValue = json[legacyKey];
  if (currentValue == null && legacyValue == null) {
    throw FormatException('Missing payment amount: $currentKey');
  }
  final current = currentValue == null
      ? null
      : _paymentPositiveInteger(currentValue, currentKey);
  final legacy = legacyValue == null
      ? null
      : _paymentPositiveInteger(legacyValue, legacyKey);
  if (current != null && legacy != null && current != legacy) {
    throw FormatException('Conflicting payment amount: $currentKey');
  }
  return current ?? legacy!;
}

double _paymentConfidence(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) {
    throw const FormatException('Invalid payment confidence');
  }
  return value.toDouble();
}

String _paymentIdentifier(Object? value, String field) {
  if (value is! String ||
      value.isEmpty ||
      value.trim() != value ||
      _paymentControlCharacter.hasMatch(value)) {
    throw FormatException('Invalid payment field: $field');
  }
  return value;
}

String _paymentOptionalText(
  Object? value,
  String field, {
  String fallback = '',
}) {
  if (value == null) return fallback;
  if (value is! String) {
    throw FormatException('Invalid payment field: $field');
  }
  return value;
}

/// Decode an actual instant, never the wall clock at the moment of decoding.
///
/// Accept zoned ISO timestamps with seconds and at most microsecond precision,
/// including PostgreSQL's +00 offset and cached UTC ISO strings. Explicit
/// DateTime instances retain their instant. Naive/date-only strings are rejected
/// rather than assigned a timezone that varies with the user's device.
DateTime _paymentTimestamp(Object? value, String field) {
  if (value is DateTime) {
    if (value.year < 1 || value.year > 9999) {
      throw FormatException('Invalid payment timestamp: $field');
    }
    return value.toUtc();
  }
  if (value is! String || value.length > 40) {
    throw FormatException('Invalid payment timestamp: $field');
  }
  final match = _paymentTimestampPattern.firstMatch(value);
  if (match == null || match.end != value.length) {
    throw FormatException('Invalid payment timestamp: $field');
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
    throw FormatException('Invalid payment timestamp: $field');
  }
  // DateTime.parse normalizes impossible calendar days. Verify the calendar
  // before parsing the offset so February 30 cannot become a valid March date.
  final calendar = DateTime.utc(year, month, day);
  if (calendar.year != year || calendar.month != month || calendar.day != day) {
    throw FormatException('Invalid payment timestamp: $field');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('Invalid payment timestamp: $field');
  }
  return parsed;
}
