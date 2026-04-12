part of 'country_catalog.dart';

abstract final class CoolCountryCatalog {
  static List<CoolCountry> all = <CoolCountry>[];

  static Future<void> initialize(String jsonString) async {
    final decoded = jsonDecode(jsonString) as List<dynamic>;
    all = decoded
        .map((e) => CoolCountry.fromJson(e as Map<String, dynamic>))
        .toList();
    if (all.isEmpty) {
      throw StateError('Country catalog loaded but found no countries.');
    }
  }

  static CoolCountry get defaultCountry => all.first;

  static CoolCountry? byIsoCode(
    String? value, {
    Iterable<CoolCountry>? source,
  }) {
    final normalized = _normalizeLookup(value);
    if (normalized.isEmpty) {
      return null;
    }
    for (final country in source ?? all) {
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
    Iterable<CoolCountry>? source,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    for (final country in source ?? all) {
      if (country.dialCode == digits) {
        return country;
      }
    }
    return null;
  }

  static CoolCountry? byProviderId(
    String? value, {
    Iterable<CoolCountry>? source,
  }) {
    final normalized = _normalizeLookup(value);
    if (normalized.isEmpty) {
      return null;
    }
    for (final country in source ?? all) {
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
    Iterable<CoolCountry>? source,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final phone = value.startsWith('+')
        ? value
        : '+${value.replaceAll(RegExp(r'[^0-9]'), '')}';
    for (final country in source ?? all) {
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
    Iterable<CoolCountry>? source,
  }) {
    final lookupSource = source ?? all;
    return byIsoCode(country, source: source) ??
        byDialCode(country, source: lookupSource) ??
        byProviderId(providerId, source: lookupSource) ??
        fromPhoneNumber(phone, source: lookupSource) ??
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
