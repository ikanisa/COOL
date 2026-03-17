import '../config/country_catalog.dart';

/// Repository for fetching and resolving supported countries.
/// Reverted from dynamic Supabase storage to synchronous hardcoded catalog
/// as part of the Rwanda-only market lock (2026-03-13).
class SupportedCountriesRepository {
  SupportedCountriesRepository();

  /// Fetches the list of active supported countries.
  /// Synchronous and does not depend on network (Rwanda-only).
  Future<List<CoolCountry>> fetchSupportedCountries({
    bool forceRefresh = false,
  }) async {
    return CoolCountryCatalog.all;
  }

  /// Synchronous access to the supported countries.
  List<CoolCountry> getSupportedCountries() {
    return CoolCountryCatalog.all;
  }

  /// Resolves the best-matching country for the current context.
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
