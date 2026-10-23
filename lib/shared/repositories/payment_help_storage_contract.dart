/// Purpose-separated protected storage. Implementations never persist plaintext
/// payment-help content or use an unprotected fallback.
abstract interface class PaymentHelpProtectedStorage {
  Future<String?> read(String ownerId);
  Future<void> write(String ownerId, String value);
  Future<void> clear(String ownerId);

  /// Includes the complete read/modify/committed-write operation. Web adapters
  /// must also serialize it across tabs, rather than just within one isolate.
  Future<T> exclusive<T>(Future<T> Function() action);
}
