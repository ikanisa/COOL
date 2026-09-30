String adminCompactTransactionReference(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) return '';
  return text.replaceAll(RegExp(r'\bCOLLECT-', caseSensitive: false), '');
}
