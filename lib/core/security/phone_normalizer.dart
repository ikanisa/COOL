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

  static String normalizeMtnMomoLocal(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('MoMo number is required');
    }

    var digits = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) digits = digits.substring(1);
    if (digits.startsWith('00')) digits = digits.substring(2);

    String? local;
    if (digits.startsWith('250') && digits.length == 12) {
      local = '0${digits.substring(3)}';
    } else if (digits.startsWith('0') && digits.length == 10) {
      local = digits;
    } else if (digits.length == 9) {
      local = '0$digits';
    }

    if (local != null && RegExp(r'^07[89][0-9]{7}$').hasMatch(local)) {
      return local;
    }

    throw const FormatException(
      'Use an MTN MoMo number, for example 0788123456',
    );
  }

  static String? tryNormalizeMtnMomoLocal(String input) {
    try {
      return normalizeMtnMomoLocal(input);
    } on FormatException {
      return null;
    }
  }
}
