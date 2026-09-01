String formatRwf(int amountRwf) {
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
