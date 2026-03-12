import 'package:cool_app/core/utils/json_helpers.dart' as jh;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/country_catalog.dart';

class SupportedCountriesRepository {
  SupportedCountriesRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  List<CoolCountry>? _cache;

  Future<List<CoolCountry>> getSupportedCountries({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cache != null && _cache!.isNotEmpty) {
      return _cache!;
    }

    try {
      final response = await _client
          .from('supported_countries')
          .select()
          .eq('is_active', true)
          .order('country_name', ascending: true);

      final countries = jh.asListOfMaps(response)
          .map(CoolCountry.fromJson)
          .where((country) {
            return country.isoCode.isNotEmpty &&
                country.dialCode.isNotEmpty &&
                country.momoUssdTemplate.isNotEmpty;
          })
          .toList(growable: false);

      if (countries.isNotEmpty) {
        _cache = countries;
        return countries;
      }
    } catch (_) {
      // Fall back to the local catalog when the DB table is unavailable.
    }

    _cache = CoolCountryCatalog.all;
    return _cache!;
  }

  Future<CoolCountry> resolveCountry({
    String? countryCode,
    String? phone,
    String? providerId,
  }) async {
    final countries = await getSupportedCountries();
    return CoolCountryCatalog.resolve(
      country: countryCode,
      phone: phone,
      providerId: providerId,
      source: countries,
    );
  }

  Future<void> clearCache() async {
    _cache = null;
  }
}
