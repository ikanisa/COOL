import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/partner.dart';

/// Repository for fetching partners from Supabase.
///
/// Partners are read-only in the client app. Admin CRUD is a future phase.
class PartnerRepository {
  PartnerRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  static const _table = 'partners';

  /// Fetch all active partners for the fixed Rwanda market.
  ///
  /// Results are ordered by `sort_order` then `name`.
  Future<List<Partner>> fetchAll() async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('is_active', true)
        .order('sort_order')
        .order('name');
    return rows.map((row) => Partner.fromJson(row)).toList();
  }

  /// Fetch a single partner by its URL slug (e.g. `rayon-sports`).
  Future<Partner?> fetchBySlug(String slug) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('slug', slug)
        .eq('is_active', true)
        .limit(1);
    if (rows.isEmpty) return null;
    return Partner.fromJson(rows.first);
  }

  /// Fetch partners filtered by [category].
  Future<List<Partner>> fetchByCategory(PartnerCategory category) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('is_active', true)
        .eq('category', category.name)
        .order('sort_order')
        .order('name');
    return rows.map((row) => Partner.fromJson(row)).toList();
  }
}
