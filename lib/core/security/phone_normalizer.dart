class PhoneNormalizer {
  const PhoneNormalizer._();

  static String normalizeInternational(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Phone number is required');
    }

    var digits = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) digits = digits.substring(1);
    if (digits.startsWith('00')) digits = digits.substring(2);

    if (RegExp(r'^[1-9][0-9]{6,14}$').hasMatch(digits)) {
      return '+$digits';
    }

    throw const FormatException('Use a valid WhatsApp phone number.');
  }

  static String normalizeForCountry({
    required String input,
    required String phoneCode,
    required String exampleNationalNumber,
  }) {
    final selectedPhoneCode = phoneCode.replaceAll(RegExp(r'\D'), '');
    final exampleDigits = exampleNationalNumber.replaceAll(RegExp(r'\D'), '');
    if (selectedPhoneCode.isEmpty || exampleDigits.isEmpty) {
      throw const FormatException('Select a valid country code.');
    }

    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Phone number is required');
    }

    final usesInternationalPrefix =
        trimmed.startsWith('+') || trimmed.startsWith('00');
    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (trimmed.startsWith('00')) digits = digits.substring(2);

    String nationalDigits;
    if (usesInternationalPrefix) {
      if (!digits.startsWith(selectedPhoneCode)) {
        throw const FormatException(
          'Phone number does not match the selected country code.',
        );
      }
      nationalDigits = digits.substring(selectedPhoneCode.length);
    } else if (digits.startsWith(selectedPhoneCode) &&
        digits.length == selectedPhoneCode.length + exampleDigits.length) {
      nationalDigits = digits.substring(selectedPhoneCode.length);
    } else {
      nationalDigits = digits.replaceFirst(RegExp(r'^0+'), '');
    }

    if (nationalDigits.length != exampleDigits.length) {
      throw FormatException(
        'Enter the complete ${exampleDigits.length}-digit phone number.',
      );
    }

    return normalizeInternational('+$selectedPhoneCode$nationalDigits');
  }

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
      'Use a Rwanda phone number, for example +250 7XX XXX XXX',
    );
  }
}
