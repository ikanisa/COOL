import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import 'admin_repository_helpers.dart';

/// Admin repository for content management: partners, services, payment
/// routes, quick actions, and app config.
class AdminContentRepository with AdminRepositoryHelpers {
  AdminContentRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  // ── Partners ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPartners({String? country}) async {
    var query = _client.from('partners').select();
    final normalizedCountry = _normalizeCountryOrNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }
    final data = await guarded(
      () => query
          .order('country', ascending: true)
          .order('sort_order', ascending: true),
      label: 'adminPartners',
    );
    return asListOfMaps(
      data,
    ).map((row) => _coerceBlankCountryToRwanda(row)).toList(growable: false);
  }

  Future<void> upsertPartner(Map<String, dynamic> partner) async {
    await guarded(
      () => _client
          .from('partners')
          .upsert(_withNormalizedCountry(partner, required: true)),
      label: 'adminUpsertPartner',
    );
  }

  Future<void> togglePartnerActive(String id, bool isActive) async {
    await guarded(
      () =>
          _client.from('partners').update({'is_active': isActive}).eq('id', id),
      label: 'adminTogglePartner',
    );
  }

  Future<void> deletePartner(String id) async {
    await guarded(
      () => _client.from('partners').delete().eq('id', id),
      label: 'adminDeletePartner',
    );
  }

  // ── Partner Services ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPartnerServices({
    String? partnerId,
    String? country,
  }) async {
    var query = _client
        .from('partner_services')
        .select('*, partners!inner(name, slug)');
    if (partnerId != null) {
      query = query.eq('partner_id', partnerId);
    }
    final data = await guarded(
      () => query
          .order('sort_order', ascending: true)
          .order('title', ascending: true),
      label: 'adminPartnerServices',
    );
    return asListOfMaps(
      data,
    ).map((row) => _coerceBlankCountryToRwanda(row)).toList(growable: false);
  }

  Future<void> upsertPartnerService(Map<String, dynamic> service) async {
    final normalizedService = _lockCountryScopeToRwanda(service);
    final partnerId = trimmed(normalizedService['partner_id']);
    if (partnerId == null) {
      throw StateError('Partner selection is required for partner services.');
    }
    normalizedService['partner_id'] = partnerId;
    await guarded(
      () => _client.from('partner_services').upsert(normalizedService),
      label: 'adminUpsertPartnerService',
    );
  }

  Future<void> deletePartnerService(String id) async {
    await guarded(
      () => _client.from('partner_services').delete().eq('id', id),
      label: 'adminDeletePartnerService',
    );
  }

  // ── Partner Payment Routes ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPartnerPaymentRoutes({
    String? partnerId,
    String? country,
  }) async {
    var query = _client
        .from('partner_payment_routes')
        .select('*, partners!inner(name, slug, country)');
    if (partnerId != null && partnerId.trim().isNotEmpty) {
      query = query.eq('partner_id', partnerId.trim());
    }
    final normalizedCountry = _normalizeCountryOrNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }
    final data = await guarded(
      () => query
          .order('country', ascending: true)
          .order('updated_at', ascending: false),
      label: 'adminPartnerPaymentRoutes',
    );
    return asListOfMaps(data)
        .map((row) {
          final normalized = _coerceBlankCountryToRwanda(row);
          final partner = row['partners'];
          if (partner is Map) {
            normalized['partner_name'] = partner['name']?.toString().trim();
            normalized['partner_slug'] = partner['slug']?.toString().trim();
            normalized['partner_country'] =
                _normalizeCountryOrNull(partner['country']?.toString()) ??
                AppMarket.countryCode;
          }
          normalized['country'] =
              _normalizeCountryOrNull(row['country']?.toString()) ??
              AppMarket.countryCode;
          normalized['provider'] = trimmed(row['provider'])?.toLowerCase();
          normalized['recipient_code'] = trimmed(row['recipient_code']);
          normalized['reconciliation_label'] = trimmed(
            row['reconciliation_label'],
          );
          normalized['status'] = trimmed(row['status'])?.toLowerCase();
          return normalized;
        })
        .toList(growable: false);
  }

  Future<void> upsertPartnerPaymentRoute(Map<String, dynamic> route) async {
    final normalized = Map<String, dynamic>.from(
      _withNormalizedCountry(route, required: true),
    );
    final partnerId = trimmed(normalized['partner_id']);
    if (partnerId == null) {
      throw StateError('Partner selection is required for payment routes.');
    }
    normalized['partner_id'] = partnerId;
    normalized['provider'] = trimmed(normalized['provider'])?.toLowerCase();
    normalized['recipient_code'] = trimmed(normalized['recipient_code']);
    normalized['reconciliation_label'] = trimmed(
      normalized['reconciliation_label'],
    );
    normalized['status'] =
        trimmed(normalized['status'])?.toLowerCase() ?? 'draft';
    await guarded(
      () => _client.from('partner_payment_routes').upsert(normalized),
      label: 'adminUpsertPartnerPaymentRoute',
    );
  }

  Future<void> deletePartnerPaymentRoute(String id) async {
    await guarded(
      () => _client.from('partner_payment_routes').delete().eq('id', id),
      label: 'adminDeletePartnerPaymentRoute',
    );
  }

  // ── Quick Actions ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchQuickActions({
    String? country,
  }) async {
    final data = await guarded(
      () => _client
          .from('quick_actions')
          .select()
          .order('sort_order', ascending: true),
      label: 'adminQuickActions',
    );
    return asListOfMaps(
      data,
    ).map((row) => _coerceBlankCountryToRwanda(row)).toList(growable: false);
  }

  Future<void> upsertQuickAction(Map<String, dynamic> action) async {
    await guarded(
      () => _client
          .from('quick_actions')
          .upsert(_lockCountryScopeToRwanda(action)),
      label: 'adminUpsertQuickAction',
    );
  }

  Future<void> deleteQuickAction(String id) async {
    await guarded(
      () => _client.from('quick_actions').delete().eq('id', id),
      label: 'adminDeleteQuickAction',
    );
  }

  Future<void> reorderQuickActions(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await guarded(
        () => _client
            .from('quick_actions')
            .update(<String, dynamic>{'sort_order': i})
            .eq('id', orderedIds[i]),
        label: 'adminReorderQuickActions',
      );
    }
  }

  // ── App Config ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAppConfig({String? country}) async {
    final data = await guarded(
      () => _client.from('app_config').select().order('key'),
      label: 'adminAppConfig',
    );
    return asListOfMaps(
      data,
    ).map((row) => _coerceBlankCountryToRwanda(row)).toList(growable: false);
  }

  Future<void> upsertAppConfig(Map<String, dynamic> config) async {
    await guarded(
      () =>
          _client.from('app_config').upsert(_lockCountryScopeToRwanda(config)),
      label: 'adminUpsertAppConfig',
    );
  }

  Future<void> upsertAppConfigs(List<Map<String, dynamic>> configs) async {
    if (configs.isEmpty) {
      return;
    }
    await guarded(
      () => _client
          .from('app_config')
          .upsert(
            configs.map(_lockCountryScopeToRwanda).toList(growable: false),
          ),
      label: 'adminUpsertAppConfigs',
    );
  }

  Future<void> deleteAppConfig(String key) async {
    await guarded(
      () => _client.from('app_config').delete().eq('key', key),
      label: 'adminDeleteAppConfig',
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────

  String? _normalizeCountryOrNull(String? country) {
    if (country == null || country.trim().isEmpty) {
      return null;
    }
    return CoolCountryCatalog.normalizeCountryCode(country);
  }

  Map<String, dynamic> _withNormalizedCountry(
    Map<String, dynamic> data, {
    bool required = false,
  }) {
    final normalizedCountry = _normalizeCountryOrNull(
      data['country']?.toString(),
    );
    final normalized = Map<String, dynamic>.from(data);
    if (required && normalizedCountry == null) {
      throw StateError('Country is required for this admin record.');
    }
    normalized['country'] = normalizedCountry;
    return normalized;
  }

  Map<String, dynamic> _coerceBlankCountryToRwanda(Map<String, dynamic> row) {
    final normalized = Map<String, dynamic>.from(row);
    if (_normalizeCountryOrNull(row['country']?.toString()) == null) {
      normalized['country'] = AppMarket.countryCode;
    }
    return normalized;
  }

  Map<String, dynamic> _lockCountryScopeToRwanda(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    normalized['country'] = AppMarket.countryCode;
    return normalized;
  }
}
