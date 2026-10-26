part of 'collect_models.dart';

// A transport precision bound shared by native and JavaScript, not a MoMo limit.
const _paymentMaxExactInteger = maxExactJsonInteger;
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

String _paymentIdentifier(Object? value, String field) =>
    exactJsonIdentifier(value, field: field);

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
DateTime _paymentTimestamp(Object? value, String field) =>
    exactJsonTimestamp(value, field: field);

String _historyUuid(Object? value, String field) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw FormatException('Invalid history identifier: $field');
  }
  return value;
}
