class PrivacyRedactor {
  /// Redacts sensitive PII from SMS text before it leaves the device.
  static String redactSms(String text) {
    var redacted = text;

    // 1. Redact Phone Numbers (Common MoMo pattern)
    // Matches typical 10-12 digit numbers or numbers starting with +
    redacted = redacted.replaceAll(RegExp(r'\+?[0-9]{10,12}'), '[PHONE_REDACTED]');

    // 2. Redact Transaction IDs / References
    // Usually alphanumeric strings of 8+ characters
    redacted = redacted.replaceAll(RegExp(r'[A-Z0-9]{8,15}'), '[REF_REDACTED]');

    // 3. Redact specific MoMo Balance patterns
    // e.g., "Balance: 150,000 RWF" -> "Balance: [HIDDEN]"
    redacted = redacted.replaceAll(RegExp(r'(Balance|Available):\s?[\d,.]+'), r'$1: [HIDDEN]');

    return redacted;
  }

  /// Provides coordinates for common ID sensitive regions for blurring.
  /// (Simplified: In production, this would use a local ML model like TFLite)
  static List<RectRegion> getSensitiveRegions(double width, double height) {
    return [
      // Signature area (usually bottom right)
      RectRegion(left: width * 0.6, top: height * 0.7, width: width * 0.35, height: height * 0.25),
      // Document Number (usually top right or bottom center)
      RectRegion(left: width * 0.5, top: height * 0.1, width: width * 0.45, height: height * 0.15),
    ];
  }
}

class RectRegion {
  RectRegion({required this.left, required this.top, required this.width, required this.height});
  final double left;
  final double top;
  final double width;
  final double height;
}
