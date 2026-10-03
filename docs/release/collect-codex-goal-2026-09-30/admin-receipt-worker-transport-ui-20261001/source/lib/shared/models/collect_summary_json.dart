part of 'collect_models.dart';

// A transport-precision bound, not a product/payment limit. Larger amounts need
// a versioned exact-integer transport before native and web can agree on them.
const _summaryMaxExactInteger = maxExactJsonInteger;

int _summaryInteger(Object? value, String field) {
  if (value is! num ||
      !value.isFinite ||
      value < -_summaryMaxExactInteger ||
      value > _summaryMaxExactInteger ||
      value.remainder(1) != 0) {
    // Field identifiers are caller-owned literals. Never echo received values.
    throw FormatException('Invalid group summary field: $field');
  }
  return value.toInt();
}

int _summaryAliasedInteger(
  Map<String, dynamic> json,
  String currentKey,
  String legacyKey,
) {
  final currentValue = json[currentKey];
  final legacyValue = json[legacyKey];
  if (currentValue == null && legacyValue == null) {
    throw FormatException('Missing group summary field: $currentKey');
  }
  final current = currentValue == null
      ? null
      : _summaryInteger(currentValue, currentKey);
  final legacy = legacyValue == null
      ? null
      : _summaryInteger(legacyValue, legacyKey);
  if (current != null && legacy != null && current != legacy) {
    throw FormatException('Conflicting group summary field: $currentKey');
  }
  return current ?? legacy!;
}

int? _summaryContributorCount(Object? value) {
  if (value == null) return null;
  final count = _summaryInteger(value, 'supporter_count');
  if (count < 0) {
    throw const FormatException('Invalid group summary field: supporter_count');
  }
  return count;
}

String _summaryCurrency(Object? value) {
  if (value == null) return 'RWF';
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid group summary field: currency');
  }
  // Preserve existing nonblank currency values; do not invent conversions or
  // change the existing modern balances-array currency allowlist here.
  return value;
}
