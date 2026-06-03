String formatRwf(int amountRwf) {
  final sign = amountRwf < 0 ? '-' : '';
  final digits = amountRwf.abs().toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index += 1) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }

  return 'RWF $sign$buffer';
}
