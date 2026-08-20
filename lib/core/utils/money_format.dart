String formatRwf(int amountRwf) {
  return formatMoneyMinor(amountRwf);
}

String formatMoneyMinor(int amountMinor, {String currency = 'EUR'}) {
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
