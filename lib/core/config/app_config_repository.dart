import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/country_catalog.dart';

/// Fetches key-value config from the `app_config` Supabase table.
class AppConfigRepository {
  AppConfigRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Cache of fetched config entries.
  final Map<String, String> _cache = {};

  /// Fetch a single config value by key and optional country.
  /// Returns the country-specific value if it exists, otherwise the global one.
  Future<String?> getValue(String key, {String? country}) async {
    final normalizedCountry = country == null || country.trim().isEmpty
        ? null
        : CoolCountryCatalog.normalizeCountryCode(country);
    final cacheKey = '${key}_${normalizedCountry ?? 'global'}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Try country-specific first
    if (normalizedCountry != null) {
      final rows = await _client
          .from('app_config')
          .select('value')
          .eq('key', key)
          .eq('country', normalizedCountry)
          .limit(1);

      if (rows.isNotEmpty) {
        final value = rows.first['value']?.toString();
        if (value != null) {
          _cache[cacheKey] = value;
          return value;
        }
      }
    }

    // Fall back to global (country IS NULL)
    final globalRows = await _client
        .from('app_config')
        .select('value')
        .eq('key', key)
        .isFilter('country', null)
        .limit(1);

    if (globalRows.isNotEmpty) {
      final value = globalRows.first['value']?.toString();
      if (value != null) {
        _cache[cacheKey] = value;
        return value;
      }
    }

    return null;
  }

  /// Fetch all config entries, optionally filtered by country.
  Future<Map<String, String>> getAll({String? country}) async {
    final normalizedCountry = country == null || country.trim().isEmpty
        ? null
        : CoolCountryCatalog.normalizeCountryCode(country);
    var query = _client.from('app_config').select();

    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }

    final rows = await query;
    final result = <String, String>{};

    for (final row in rows) {
      final key = row['key']?.toString();
      final value = row['value']?.toString();
      if (key != null && value != null) {
        // Country-specific values override global ones
        final rowCountry = row['country']?.toString();
        if (rowCountry != null || !result.containsKey(key)) {
          result[key] = value;
        }
      }
    }

    _cache.addAll(result);
    return result;
  }

  /// Convenience: parse the supported_languages JSON config value.
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    final raw = await getValue('supported_languages');
    if (raw == null) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => m.map((k, v) => MapEntry(k, v.toString())))
            .toList();
      }
    } catch (_) {
      // Fall through to empty
    }
    return const [];
  }

  /// Convenience: get the support WhatsApp number.
  Future<String> getSupportWhatsApp({String? country}) async {
    return await getValue('support_whatsapp', country: country) ??
        '250795588248';
  }

  /// Convenience: get credit grade thresholds.
  Future<({int excellent, int good, int building})> getCreditGrades() async {
    final excellent =
        int.tryParse(await getValue('credit_grade_excellent') ?? '') ?? 80;
    final good = int.tryParse(await getValue('credit_grade_good') ?? '') ?? 60;
    final building =
        int.tryParse(await getValue('credit_grade_building') ?? '') ?? 40;

    return (excellent: excellent, good: good, building: building);
  }

  /// Convenience: get default map coordinates for a country.
  Future<({double lat, double lng})?> getDefaultMapCenter({
    String? country,
  }) async {
    final latStr = await getValue('default_map_lat', country: country);
    final lngStr = await getValue('default_map_lng', country: country);

    if (latStr == null || lngStr == null) return null;

    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);

    if (lat == null || lng == null) return null;

    return (lat: lat, lng: lng);
  }

  /// Clear the in-memory cache.
  void clearCache() => _cache.clear();
}
