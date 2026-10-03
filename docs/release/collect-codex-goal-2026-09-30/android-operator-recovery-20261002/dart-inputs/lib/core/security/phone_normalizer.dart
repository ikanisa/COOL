class PhoneNormalizer {
  const PhoneNormalizer._();

  static String normalizeRwanda(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Phone number is required');
    }

    var digits = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) digits = digits.substring(1);
    if (digits.startsWith('00')) digits = digits.substring(2);

    final normalized = switch (digits) {
      _ when digits.startsWith('250') && digits.length == 12 => '+$digits',
      _ when digits.startsWith('0') && digits.length == 10 =>
        '+250${digits.substring(1)}',
      _ when digits.length == 9 => '+250$digits',
      _ => '',
    };
    if (RegExp(r'^\+2507[2389][0-9]{7}$').hasMatch(normalized)) {
      return normalized;
    }
    throw const FormatException(
      'Use a Rwanda mobile number, for example +250 7XX XXX XXX',
    );
  }
}
