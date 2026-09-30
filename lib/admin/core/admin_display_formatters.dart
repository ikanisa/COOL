String adminCompactTransactionReference(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) return '';
  return text.replaceAll(RegExp(r'\bCOLLECT-', caseSensitive: false), '');
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
