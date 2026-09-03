/// Matches the server-side member profile contract. A host suffix alone is
/// insufficient: it accepts look-alike domains, insecure schemes and empty paths.
abstract final class CollectDiasporaProfileRules {
  static final _link = RegExp(
    r'^https://([a-z0-9-]+\.)?revolut\.me/[A-Za-z0-9._~-]+/?$',
  );

  static bool isValidLink(String value) => _link.hasMatch(value.trim());

  static bool isValidAccount(String value) {
    // PostgreSQL char_length counts Unicode characters, not UTF-16 code units.
    final length = value.trim().runes.length;
    return length >= 4 && length <= 120;
  }
}
