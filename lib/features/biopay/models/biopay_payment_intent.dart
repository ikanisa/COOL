/// Server-issued, time-limited, one-time-use payment intent
/// that binds a biometric match to a specific payment action.
class BiopayPaymentIntent {
  const BiopayPaymentIntent({
    required this.intentId,
    required this.nonce,
    required this.ussdCode,
    required this.expiresAt,
    required this.displayName,
  });

  factory BiopayPaymentIntent.fromApiResponse(Map<String, dynamic> data) {
    return BiopayPaymentIntent(
      intentId: data['intent_id']?.toString() ?? '',
      nonce: data['nonce']?.toString() ?? '',
      ussdCode: data['ussd_code']?.toString() ?? '',
      expiresAt:
          DateTime.tryParse(data['expires_at']?.toString() ?? '') ??
          DateTime.now(),
      displayName: data['display_name']?.toString() ?? '',
    );
  }

  final String intentId;
  final String nonce;
  final String ussdCode;
  final DateTime expiresAt;
  final String displayName;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Build the tel: URI for dialing the server-issued USSD code.
  Uri get dialUri => Uri.parse('tel:${ussdCode.replaceAll('#', '%23')}');
}
