part of 'country_catalog.dart';

abstract final class CoolCountryCatalog {
  static const List<CoolCountry> all = <CoolCountry>[
    CoolCountry(
      isoCode: 'RW',
      dialCode: '+250',
      name: 'Rwanda',
      flagEmoji: '🇷🇼',
      currencyCode: 'RWF',
      currencyName: 'Rwandan franc',
      momoUssdTemplate: '*182*1*1*{recipient}*{amount}#',
      momoCodeUssdTemplate: '*182*8*1*{recipient}*{amount}#',
      aliases: <String>['Rwanda'],
      providerAliases: <String>['mtn_rwanda', 'mtn', 'mtn rwanda'],
      mobileNationalNumberPattern: r'^0?7[23589]\d{7}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0781234567',
      mobileExampleE164: '+250781234567',
      momoNumberLocalPattern: r'^0?7[23589]\d{7}$',
      momoNumberE164Pattern: r'^\+2507[23589]\d{7}$',
      momoCodePattern: r'^\d{4,9}$',
      momoCodeMinLength: 4,
      momoCodeMaxLength: 9,
      momoCodeExample: '123456',
    ),
  ];

  static CoolCountry get defaultCountry => all.first;

  static CoolCountry? byIsoCode(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    final normalized = _normalizeLookup(value);
    if (normalized.isEmpty) {
      return null;
    }
    for (final country in source) {
      if (country.isoCode.toLowerCase() == normalized) {
        return country;
      }
      for (final alias in country.aliases) {
        if (_normalizeLookup(alias) == normalized) {
          return country;
        }
      }
    }
    return null;
  }

  static CoolCountry? byDialCode(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    for (final country in source) {
      if (country.dialCode == digits) {
        return country;
      }
    }
    return null;
  }

  static CoolCountry? byProviderId(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    final normalized = _normalizeLookup(value);
    if (normalized.isEmpty) {
      return null;
    }
    for (final country in source) {
      if (_normalizeLookup(country.providerId) == normalized) {
        return country;
      }
      for (final alias in country.providerAliases) {
        if (_normalizeLookup(alias) == normalized) {
          return country;
        }
      }
    }
    return null;
  }

  static CoolCountry? fromPhoneNumber(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final phone = value.startsWith('+')
        ? value
        : '+${value.replaceAll(RegExp(r'[^0-9]'), '')}';
    for (final country in source) {
      if (phone.startsWith(country.dialCode)) {
        return country;
      }
    }
    return null;
  }

  static CoolCountry resolve({
    String? country,
    String? phone,
    String? providerId,
    Iterable<CoolCountry> source = all,
  }) {
    return byIsoCode(country, source: source) ??
        byDialCode(country, source: source) ??
        byProviderId(providerId, source: source) ??
        fromPhoneNumber(phone, source: source) ??
        defaultCountry;
  }

  static String normalizeCountryCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return defaultCountry.isoCode;
    }
    return byIsoCode(value)?.isoCode ??
        byDialCode(value)?.isoCode ??
        fromPhoneNumber(value)?.isoCode ??
        value.trim().toUpperCase();
  }

  static String normalizeProviderId({
    String? providerId,
    String? country,
    String? phone,
  }) {
    final resolvedCountry =
        byIsoCode(country) ??
        byDialCode(country) ??
        fromPhoneNumber(phone) ??
        byProviderId(providerId);

    if (resolvedCountry != null) {
      return resolvedCountry.providerId;
    }

    if (providerId != null && providerId.trim().isNotEmpty) {
      return providerId.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    }

    final normalizedCountry = country?.trim().toLowerCase();
    if (normalizedCountry != null && normalizedCountry.isNotEmpty) {
      return 'momo_$normalizedCountry';
    }

    return '';
  }

  static String _normalizeLookup(String? value) {
    return value
            ?.toLowerCase()
            .replaceAll('&', 'and')
            .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
            .trim() ??
        '';
  }
}
