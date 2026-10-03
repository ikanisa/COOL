/// Collect operates in Rwanda with RWF and Rwanda MoMo only.
abstract final class CollectProfileCountryRules {
  static String normalizeCountryCode(String? value) =>
      (value ?? '').trim().toUpperCase();

  static bool isSupportedCountry(String? countryCode) =>
      normalizeCountryCode(countryCode) == 'RW';

  static String currencyForCountry(String? countryCode) =>
      isSupportedCountry(countryCode) ? 'RWF' : 'XXX';

  static String resolveCountryCode({
    required String? storedCountryCode,
    required String whatsappPhone,
    String fallback = 'RW',
  }) =>
      isSupportedCountry(storedCountryCode) ||
          whatsappPhone.replaceAll(RegExp(r'\D'), '').startsWith('250')
      ? 'RW'
      : '';

  static String inferCountryCodeFromPhone(
    String phone, {
    String fallback = 'RW',
  }) => phone.replaceAll(RegExp(r'\D'), '').startsWith('250') ? 'RW' : '';
}
