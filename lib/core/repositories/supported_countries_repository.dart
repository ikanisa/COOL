import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/country_catalog.dart';

/// Repository for fetching and resolving supported countries.
/// Migrated from hardcoded catalog to dynamic Supabase storage.
class SupportedCountriesRepository {
  SupportedCountriesRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  /// Cache for fetched countries.
  List<CoolCountry>? _cachedCountries;

  /// Fetches the list of active supported countries from Supabase.
  /// Falls back to the hardcoded [CoolCountryCatalog.all] if fetch fails or is empty.
  Future<List<CoolCountry>> fetchSupportedCountries({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedCountries != null) {
      return _cachedCountries!;
    }

    try {
      final response = await _client
          .from('supported_countries')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final List<dynamic> data = response as List<dynamic>;
      if (data.isEmpty) {
        return _useFallback();
      }

      final countries = data
          .map(
            (json) =>
                CoolCountry.fromJson(Map<String, dynamic>.from(json as Map)),
          )
          .toList(growable: false);

      _cachedCountries = countries;
      return countries;
    } catch (e) {
      // Log error in a real app, here we just fallback for resilience
      return _useFallback();
    }
  }

  /// Synchronous access to the last fetched countries.
  /// Defaults to hardcoded fallback if not yet fetched.
  List<CoolCountry> getSupportedCountries() {
    return _cachedCountries ?? CoolCountryCatalog.all;
  }

  /// Resolves any combination of country/phone/providerId to a country.
  /// Uses the dynamic catalog if available, otherwise falls back to hardcoded.
  CoolCountry resolveCountry({
    String? countryCode,
    String? phone,
    String? providerId,
  }) {
    return CoolCountryCatalog.resolve(
      country: countryCode,
      phone: phone,
      providerId: providerId,
      source: getSupportedCountries(),
    );
  }

  List<CoolCountry> _useFallback() {
    _cachedCountries = CoolCountryCatalog.all;
    return CoolCountryCatalog.all;
  }
}
