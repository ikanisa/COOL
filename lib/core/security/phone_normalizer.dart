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

    if (digits.startsWith('250') && digits.length == 12) {
      return '+$digits';
    }
    if (digits.startsWith('0') && digits.length == 10) {
      return '+250${digits.substring(1)}';
    }
    if (digits.length == 9 && RegExp(r'^[2378]').hasMatch(digits)) {
      return '+250$digits';
    }

    throw const FormatException(
      'Use a Rwanda phone number, for example +250788123456',
    );
  }
}
