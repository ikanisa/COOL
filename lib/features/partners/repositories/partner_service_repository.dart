import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/partner_service.dart';

/// Fetches partner services from the `partner_services` Supabase table.
class PartnerServiceRepository {
  PartnerServiceRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  /// Fetch all active services for a specific partner.
  Future<List<PartnerService>> fetchByPartnerId(String partnerId) async {
    final rows = await _client
        .from('partner_services')
        .select()
        .eq('partner_id', partnerId)
        .eq('is_active', true)
        .order('sort_order')
        .order('title');

    return rows.map((r) => PartnerService.fromJson(r)).toList();
  }

  /// Fetch services filtered by partner and category.
  Future<List<PartnerService>> fetchByCategory(
    String partnerId,
    String category,
  ) async {
    final rows = await _client
        .from('partner_services')
        .select()
        .eq('partner_id', partnerId)
        .eq('category', category)
        .eq('is_active', true)
        .order('sort_order');

    return rows.map((r) => PartnerService.fromJson(r)).toList();
  }
}
