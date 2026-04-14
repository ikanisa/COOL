import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_query_helpers.dart' as sq;

abstract final class AppConfigKeys {
  static const biopayEnabled = 'feature_biopay_enabled';
  static const biopayMatchThreshold = 'biopay_match_threshold';
  static const biopayCacheTtlHours = 'biopay_cache_ttl_hours';
  static const biopayStableFrames = 'biopay_stable_frames';
}

/// Fetches key-value config from the `app_config` Supabase table.
class AppConfigRepository {
  AppConfigRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Cache of fetched config entries.
  final Map<String, String> _cache = {};

  /// Fetch a single config value by key.
  Future<String?> getValue(String key, {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache.containsKey(key)) {
      return _cache[key];
    }
    if (forceRefresh) {
      _cache.remove(key);
    }

    final rows = sq.asListOfMaps(
      await sq.guarded(
        () =>
            _client.from('app_config').select('value').eq('key', key).limit(1),
        label: 'appConfigValue',
      ),
    );

    if (rows.isNotEmpty) {
      final value = rows.first['value']?.toString();
      if (value != null) {
        _cache[key] = value;
        return value;
      }
    }

    return null;
  }

  /// Fetch all config entries for the fixed Rwanda app shell.
  Future<Map<String, String>> getAll() async {
    final rows = sq.asListOfMaps(
      await sq.guarded(
        () => _client.from('app_config').select(),
        label: 'appConfigAll',
      ),
    );
    final result = <String, String>{};

    for (final row in rows) {
      final key = row['key']?.toString();
      final value = row['value']?.toString();
      if (key != null && value != null) {
        result[key] = value;
      }
    }

    _cache.addAll(result);
    return result;
  }

  /// Rwanda-only: English is the only supported language.
  List<Map<String, String>> getSupportedLanguages() {
    return const [
      {'code': 'en', 'name': 'English'},
    ];
  }

  /// Convenience: get the support WhatsApp number.
  Future<String> getSupportWhatsApp() async {
    return await getValue('support_whatsapp') ?? '250795588248';
  }

  /// Fetches default map center from app config (falls back to Kigali).
  Future<({double lat, double lng})> getDefaultMapCenter() async {
    final lat =
        double.tryParse(await getValue('default_map_lat') ?? '') ?? -1.9403;
    final lng =
        double.tryParse(await getValue('default_map_lng') ?? '') ?? 29.8739;
    return (lat: lat, lng: lng);
  }

  /// Clear the in-memory cache.
  void clearCache() => _cache.clear();
}
