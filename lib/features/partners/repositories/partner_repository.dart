import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../models/partner.dart';

/// Repository for fetching partners from Supabase.
///
/// Partners are read-only in the client app. Admin CRUD is a future phase.
class PartnerRepository {
  PartnerRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _table = 'partners';

  /// Fetch all active partners, optionally filtered by [country].
  ///
  /// Results are ordered by `sort_order` then `name`.
  Future<List<Partner>> fetchAll({String? country}) async {
    var query = _client.from(_table).select().eq('is_active', true);

    if (country != null && country.isNotEmpty) {
      query = query.eq(
        'country',
        CoolCountryCatalog.normalizeCountryCode(country),
      );
    }

    final rows = await query.order('sort_order').order('name');
    return rows.map((row) => Partner.fromJson(row)).toList();
  }

  /// Fetch a single partner by its URL slug (e.g. `rayon-sports`).
  Future<Partner?> fetchBySlug(String slug, {String? country}) async {
    var query = _client
        .from(_table)
        .select()
        .eq('slug', slug)
        .eq('is_active', true);
    if (country != null && country.isNotEmpty) {
      query = query.eq(
        'country',
        CoolCountryCatalog.normalizeCountryCode(country),
      );
    }

    final rows = await query.limit(1);
    if (rows.isEmpty) return null;
    return Partner.fromJson(rows.first);
  }

  /// Fetch partners filtered by [category] and optionally [country].
  Future<List<Partner>> fetchByCategory(
    PartnerCategory category, {
    String? country,
  }) async {
    var query = _client
        .from(_table)
        .select()
        .eq('is_active', true)
        .eq('category', category.name);

    if (country != null && country.isNotEmpty) {
      query = query.eq(
        'country',
        CoolCountryCatalog.normalizeCountryCode(country),
      );
    }

    final rows = await query.order('sort_order').order('name');
    return rows.map((row) => Partner.fromJson(row)).toList();
  }
}
