import 'package:intl/intl.dart';

String formatRwf(int amountRwf, {String? localeName}) {
  if (localeName != null && localeName.trim().isNotEmpty) {
    try {
      return NumberFormat.currency(
        locale: localeName,
        name: 'RWF',
        symbol: 'RWF ',
        decimalDigits: 0,
      ).format(amountRwf);
    } on ArgumentError {
      // A newly introduced device locale must not break a payment surface.
    }
  }
  final sign = amountRwf < 0 ? '-' : '';
  final digits = amountRwf.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index += 1) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return 'RWF $sign$buffer';
}

String formatMoneyMinor(
  int amountMinor, {
  String currency = 'EUR',
  String? localeName,
}) {
  if (currency.trim().toUpperCase() == 'RWF') {
    return formatRwf(amountMinor, localeName: localeName);
  }
  if (localeName != null && localeName.trim().isNotEmpty) {
    try {
      return NumberFormat.currency(
        locale: localeName,
        name: currency.toUpperCase(),
        symbol: '${currency.toUpperCase()} ',
        decimalDigits: 2,
      ).format(amountMinor / 100);
    } on ArgumentError {
      // Preserve the deterministic ISO-code fallback below.
    }
  }
  final sign = amountMinor < 0 ? '-' : '';
  final absolute = amountMinor.abs();
  final whole = absolute ~/ 100;
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index += 1) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return '${currency.toUpperCase()} $sign$buffer.$fraction';
}

/// Amounts stay in their settlement currency. This never performs FX conversion.
String formatCurrencyTotals(
  Map<String, int> totals, {
  String emptyCurrency = 'RWF',
  String separator = ' · ',
}) {
  if (totals.isEmpty) return formatMoneyMinor(0, currency: emptyCurrency);
  final currencies = totals.keys.toList()..sort();
  return currencies
      .map(
        (currency) => formatMoneyMinor(totals[currency]!, currency: currency),
      )
      .join(separator);
}
