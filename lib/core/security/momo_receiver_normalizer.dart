class MomoReceiverNormalizer {
  const MomoReceiverNormalizer._();

  static const int minPayCodeLength = 4;
  static const int maxPayCodeLength = 9;
  static const String payCodeErrorMessage = 'Use a 4 to 9 digit MoMo code.';

  static String normalizePayCode(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= minPayCodeLength &&
        digits.length <= maxPayCodeLength) {
      return digits;
    }
    throw const FormatException(payCodeErrorMessage);
  }

  static String? tryNormalizePayCode(String input) {
    try {
      return normalizePayCode(input);
    } on FormatException {
      return null;
    }
  }
}
