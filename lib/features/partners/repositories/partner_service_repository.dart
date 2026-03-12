import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../models/partner_service.dart';

/// Fetches partner services from the `partner_services` Supabase table.
class PartnerServiceRepository {
  PartnerServiceRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Fetch all active services for a specific partner.
  Future<List<PartnerService>> fetchByPartnerId(
    String partnerId, {
    String? country,
  }) async {
    var query = _client
        .from('partner_services')
        .select()
        .eq('partner_id', partnerId)
        .eq('is_active', true);

    if (country != null && country.trim().isNotEmpty) {
      final normalizedCountry = CoolCountryCatalog.normalizeCountryCode(
        country,
      );
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }

    final rows = await query.order('sort_order').order('title');

    return rows.map((r) => PartnerService.fromJson(r)).toList();
  }

  /// Fetch services filtered by partner and category.
  Future<List<PartnerService>> fetchByCategory(
    String partnerId,
    String category, {
    String? country,
  }) async {
    var query = _client
        .from('partner_services')
        .select()
        .eq('partner_id', partnerId)
        .eq('category', category)
        .eq('is_active', true);

    if (country != null && country.trim().isNotEmpty) {
      final normalizedCountry = CoolCountryCatalog.normalizeCountryCode(
        country,
      );
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }

    final rows = await query.order('sort_order');

    return rows.map((r) => PartnerService.fromJson(r)).toList();
  }
}
