import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../models/quick_action.dart';

/// Fetches quick action cards from the `quick_actions` Supabase table.
class QuickActionRepository {
  QuickActionRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Fetch all active quick actions, optionally filtered by country.
  Future<List<QuickAction>> fetchAll({String? country}) async {
    var query = _client.from('quick_actions').select().eq('is_active', true);

    // Show global actions (country IS NULL) and country-specific ones
    if (country != null && country.trim().isNotEmpty) {
      final normalizedCountry = CoolCountryCatalog.normalizeCountryCode(
        country,
      );
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }

    final rows = await query.order('sort_order').order('title');
    return rows.map((r) => QuickAction.fromJson(r)).toList();
  }
}
