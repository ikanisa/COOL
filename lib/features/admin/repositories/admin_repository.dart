import 'package:supabase_flutter/supabase_flutter.dart';

/// Central repository for admin CRUD operations across all dynamic content tables.
class AdminRepository {
  AdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  // ── Users ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final data = await _client
        .from('users')
        .select(
          'id, full_name, phone, country, language_code, '
          'momo_provider, is_driver, vehicle_type, is_admin, '
          'created_at, is_mock, mock_batch',
        )
        .order('is_mock', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> purgeMockBatch(String batch) async {
    final data = await _client.rpc(
      'purge_mock_batch',
      params: <String, dynamic>{'p_mock_batch': batch},
    );
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('Expected purge_mock_batch to return a JSON object.');
  }

  // ── Partners ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPartners() async {
    final data = await _client
        .from('partners')
        .select()
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertPartner(Map<String, dynamic> partner) async {
    await _client.from('partners').upsert(partner);
  }

  Future<void> togglePartnerActive(String id, bool isActive) async {
    await _client.from('partners').update({'is_active': isActive}).eq('id', id);
  }

  Future<void> deletePartner(String id) async {
    await _client.from('partners').delete().eq('id', id);
  }

  // ── Partner Services ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPartnerServices({
    String? partnerId,
  }) async {
    var query = _client
        .from('partner_services')
        .select('*, partners!inner(name, slug)');
    if (partnerId != null) {
      query = query.eq('partner_id', partnerId);
    }
    final data = await query.order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertPartnerService(Map<String, dynamic> service) async {
    await _client.from('partner_services').upsert(service);
  }

  Future<void> deletePartnerService(String id) async {
    await _client.from('partner_services').delete().eq('id', id);
  }

  // ── Quick Actions ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchQuickActions() async {
    final data = await _client
        .from('quick_actions')
        .select()
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertQuickAction(Map<String, dynamic> action) async {
    await _client.from('quick_actions').upsert(action);
  }

  Future<void> deleteQuickAction(String id) async {
    await _client.from('quick_actions').delete().eq('id', id);
  }

  Future<void> reorderQuickActions(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _client
          .from('quick_actions')
          .update(<String, dynamic>{'sort_order': i})
          .eq('id', orderedIds[i]);
    }
  }

  // ── Vehicle Types ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchVehicleTypes() async {
    final data = await _client
        .from('vehicle_types')
        .select()
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertVehicleType(Map<String, dynamic> type) async {
    await _client.from('vehicle_types').upsert(type);
  }

  Future<void> deleteVehicleType(String id) async {
    await _client.from('vehicle_types').delete().eq('id', id);
  }

  // ── Supported Countries ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchCountries() async {
    final data = await _client
        .from('supported_country_momo_reference')
        .select()
        .order('sort_order', ascending: true)
        .order('country_name', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> fetchMomoValidationIssues() async {
    final data = await _client.rpc('get_momo_validation_issues');
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<Map<String, dynamic>> repairMomoValidationIssue({
    required String recordType,
    required String recordId,
    required String issueCode,
  }) async {
    final data = await _client.rpc(
      'repair_momo_validation_issue',
      params: <String, dynamic>{
        'p_record_type': recordType,
        'p_record_id': recordId,
        'p_issue_code': issueCode,
      },
    );

    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw StateError('Expected repair_momo_validation_issue to return JSON.');
  }

  Future<void> updateCountry(
    String isoCode,
    Map<String, dynamic> updates,
  ) async {
    await _client
        .from('supported_countries')
        .update(updates)
        .eq('iso_code', isoCode);
  }

  // ── App Config ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAppConfig() async {
    final data = await _client
        .from('app_config')
        .select()
        .order('key', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertAppConfig(Map<String, dynamic> config) async {
    await _client.from('app_config').upsert(config);
  }

  Future<void> deleteAppConfig(String key) async {
    await _client.from('app_config').delete().eq('key', key);
  }
}
