String adminCompactTransactionReference(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) return '';
  return text.replaceAll(RegExp(r'\bCOLLECT-', caseSensitive: false), '');
}

/// Group an integer decimal string without converting money through double.
/// The input is already a display amount; invalid grouping stays unchanged.
String adminFormatRwfAmount(String value) {
  final match = RegExp(
    r'^RWF\s+(-?)([0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(\s*=)?$',
  ).firstMatch(value.trim());
  if (match == null) return value;
  final raw = match[2]!.replaceAll(',', '').replaceFirst(RegExp(r'^0+'), '');
  final digits = raw.isEmpty ? '0' : raw;
  final sign = digits == '0' ? '' : match[1]!;
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return 'RWF $sign$grouped${match[3] == null ? '' : ' ='}';
}

/// Format an exact integer amount without repeating the local currency code.
String adminFormatWholeAmount(Object? value) {
  final digits = '${value ?? ''}'.trim();
  if (!RegExp(r'^-?[0-9]+$').hasMatch(digits)) return digits;
  final negative = digits.startsWith('-');
  final whole = negative ? digits.substring(1) : digits;
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) grouped.write(',');
    grouped.write(whole[index]);
  }
  return '${negative ? '-' : ''}$grouped';
}

/// Collect operations use Africa/Kigali (UTC+2 throughout the year), regardless
/// of the operator's browser or device timezone.
DateTime? _kigali(DateTime? value) =>
    value?.toUtc().add(const Duration(hours: 2));

String adminKigaliDate(DateTime? value) {
  final time = _kigali(value);
  if (time == null) return '—';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${time.day} ${months[time.month - 1]} ${time.year}';
}

String adminKigaliTime(DateTime? value) {
  final time = _kigali(value);
  if (time == null) return '—';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}';
}

String adminKigaliDateTime(DateTime? value, {bool includeZone = true}) {
  if (value == null) return '—';
  final zone = includeZone ? ' · Africa/Kigali' : '';
  return '${adminKigaliDate(value)} · ${adminKigaliTime(value)}$zone';
}
