import '../config/country_catalog.dart';

/// The COOL app is Rwanda-only. This repository always returns Rwanda.
///
/// The Supabase `supported_countries` table is no longer queried.
class SupportedCountriesRepository {
  SupportedCountriesRepository();

  List<CoolCountry> getSupportedCountries() => CoolCountryCatalog.all;

  CoolCountry resolveCountry({
    String? countryCode,
    String? phone,
    String? providerId,
  }) {
    return CoolCountryCatalog.resolve(
      country: countryCode,
      phone: phone,
      providerId: providerId,
    );
  }
}
