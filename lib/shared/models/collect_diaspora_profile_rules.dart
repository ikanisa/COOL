/// Account-number syntax shared with the server profile gate. This does not
/// establish bank ownership or that an account exists.
abstract final class CollectDiasporaProfileRules {
  static final _link = RegExp(
    r'^https://([a-z0-9-]+\.)?revolut\.me/[A-Za-z0-9._~-]+/?$',
  );

  static bool isValidLink(String value) => _link.hasMatch(value.trim());

  static bool isValidAccount(String value) {
    final account = normalizeAccount(value);
    return RegExp(r'^[A-Z0-9]{4,34}$').hasMatch(account) &&
        RegExp(r'[0-9]').hasMatch(account);
  }

  static String normalizeAccount(String value) =>
      value.trim().replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
}
