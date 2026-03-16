import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class AppConfigKeys {
  static const mobilitySubscriptionMomoCode = 'mobility_subscription_momo_code';
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

    final rows = await _client
        .from('app_config')
        .select('value')
        .eq('key', key)
        .limit(1);

    if (rows.isNotEmpty) {
      final value = rows.first['value']?.toString();
      if (value != null) {
        _cache[key] = value;
        return value;
      }
    }

    return null;
  }

  Future<String?> getMobilitySubscriptionMomoCode({
    bool forceRefresh = false,
  }) async {
    final value = await getValue(
      AppConfigKeys.mobilitySubscriptionMomoCode,
      forceRefresh: forceRefresh,
    );
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Fetch all config entries for the fixed Rwanda app shell.
  Future<Map<String, String>> getAll() async {
    final rows = await _client.from('app_config').select();
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

  /// Convenience: get credit grade thresholds.
  Future<({int excellent, int good, int building})> getCreditGrades() async {
    final excellent =
        int.tryParse(await getValue('credit_grade_excellent') ?? '') ?? 80;
    final good = int.tryParse(await getValue('credit_grade_good') ?? '') ?? 60;
    final building =
        int.tryParse(await getValue('credit_grade_building') ?? '') ?? 40;

    return (excellent: excellent, good: good, building: building);
  }

  /// Fetches default map center from app config (falls back to Kigali).
  Future<({double lat, double lng})> getDefaultMapCenter() async {
    final lat = double.tryParse(await getValue('default_map_lat') ?? '') ?? -1.9403;
    final lng = double.tryParse(await getValue('default_map_lng') ?? '') ?? 29.8739;
    return (lat: lat, lng: lng);
  }

  /// Clear the in-memory cache.
  void clearCache() => _cache.clear();
}
