/// Presentation-only safeguards for preserved SMS evidence in Collect Admin.
///
/// Masking is defense in depth: the API must still authorize and redact data.
/// None of these descriptions represents mobile-money settlement status.
class AdminReceiptPresentation {
  const AdminReceiptPresentation._();

  /// Never echo a contact value from a list/detail projection, even if its
  /// source field is named `payer_masked_phone`. Reveal at most three digits.
  static String maskedContact(Object? source) {
    final raw = source?.toString().trim() ?? '';
    if (raw.isEmpty || raw == '—') return '—';
    final digits = RegExp(r'[0-9]')
        .allMatches(raw)
        .map((match) => match.group(0)!)
        .join();
    if (digits.length < 3) return '••••';
    return '•••• ${digits.substring(digits.length - 3)}';
  }

  /// An absent, malformed or negative conflict count is unknown, not zero.
  static int? nonNegativeCount(Object? value) {
    if (value is int) return value >= 0 ? value : null;
    if (value is! String) return null;
    final raw = value.trim();
    if (!RegExp(r'^[0-9]{1,10}$').hasMatch(raw)) return null;
    final result = int.tryParse(raw);
    return result != null && result >= 0 ? result : null;
  }

  static String conflicts(Object? value) {
    final count = nonNegativeCount(value);
    if (count == null) return 'Conflict count unavailable';
    if (count == 0) return 'No conflicting references';
    return '$count conflicting ${count == 1 ? 'reference' : 'references'}';
  }

  static String extraction(Object? value, {bool sourceMetadata = false}) {
    if (sourceMetadata) return 'Source metadata';
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 'Extraction not established';
    return text.split('_').map((word) => word.isEmpty
        ? word
        : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
  }
}
