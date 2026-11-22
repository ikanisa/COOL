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
      // An unsupported device locale must not break a payment surface.
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
  String currency = 'RWF',
  String? localeName,
}) {
  if (currency.trim().toUpperCase() != 'RWF') {
    throw const FormatException('Only RWF MoMo amounts are supported');
  }
  return formatRwf(amountMinor, localeName: localeName);
}

String formatCurrencyTotals(
  Map<String, int> totals, {
  String emptyCurrency = 'RWF',
  String separator = ' · ',
}) {
  if (emptyCurrency.trim().toUpperCase() != 'RWF' ||
      totals.keys.any((currency) => currency != 'RWF')) {
    throw const FormatException('Only RWF MoMo totals are supported');
  }
  return formatRwf(totals['RWF'] ?? 0);
}
