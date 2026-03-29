import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import 'admin_repository_helpers.dart';
import 'admin_user_row_normalizer.dart';

/// Core admin repository for country reference data, operational dashboards,
/// platform analytics, and audit log.
///
/// Content management (partners, services, payment routes, quick actions,
/// vehicle types, app config) has been extracted to [AdminContentRepository].
///
/// MoMo operational views (sender inventory, manual review, health events,
/// validation issues) have been extracted to [AdminMomoOpsRepository].
///
/// User management (inventory, profile updates, mock cleanup) has been
/// extracted to [AdminUsersRepository].
class AdminRepository with AdminRepositoryHelpers {
  AdminRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  static const String _countryReferenceSelect =
      'iso_code, country_name, flag_emoji, dial_code, currency_code, '
      'currency_name, momo_provider_id, country_aliases, '
      'momo_provider_aliases, mobile_national_number_pattern, '
      'mobile_possible_lengths, mobile_example_national, '
      'mobile_example_e164, momo_number_local_pattern, '
      'momo_number_e164_pattern, momo_number_ussd_template, '
      'momo_number_ussd_regex, momo_number_ussd_example, momo_code_kind, '
      'momo_code_pattern, momo_code_min_length, momo_code_max_length, '
      'momo_code_example, momo_code_ussd_template, momo_code_ussd_regex, '
      'momo_code_ussd_example, phone_validation_source, momo_ussd_source, '
      'validation_notes, default_lat, default_lng, sort_order, is_active, '
      'updated_at';

  // ── Supported Countries ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchCountries() async {
    try {
      final data = await _client
          .from('supported_country_momo_reference')
          .select()
          .order('sort_order', ascending: true)
          .order('country_name', ascending: true);
      return _normalizeCountryReferenceRows(data);
    } on PostgrestException catch (error) {
      if (!isMissingSchemaObjectError(error)) {
        rethrow;
      }
    }

    try {
      final data = await _client
          .from('supported_countries')
          .select(_countryReferenceSelect)
          .order('sort_order', ascending: true)
          .order('country_name', ascending: true);
      return _normalizeCountryReferenceRows(data);
    } on PostgrestException catch (error) {
      if (!isMissingSchemaObjectError(error)) {
        rethrow;
      }
    } catch (_) {
      return _catalogCountryReferenceRows();
    }

    return _catalogCountryReferenceRows();
  }

  // ── Operational Dashboard ─────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchOperationalReleaseDashboard() async {
    final data = await _client.rpc('get_operational_release_dashboard');
    return asListOfMaps(data);
  }

  Future<List<Map<String, dynamic>>> fetchOperationalTriageIssues() async {
    final data = await _client.rpc('get_operational_triage_issues');
    return asListOfMaps(data);
  }

  // ── Platform Analytics ────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchPlatformAnalytics() async {
    final data = await _client.rpc('get_platform_analytics_summary');
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Expected get_platform_analytics_summary to return JSON.');
  }

  // ── Audit Log ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAuditLog({
    int limit = 50,
    int offset = 0,
    String? action,
    String? actorId,
  }) async {
    final data = await _client.rpc(
      'get_admin_audit_log',
      params: <String, dynamic>{
        'p_limit': limit,
        'p_offset': offset,
        ...?(action == null ? null : <String, dynamic>{'p_action': action}),
        ...?(actorId == null ? null : <String, dynamic>{'p_actor_id': actorId}),
      },
    );
    return asListOfMaps(data);
  }

  // ── Private helpers ───────────────────────────────────────────────────

  /// Admin consumers should never receive off-market or non-English user
  /// scope, even if legacy rows still exist in storage.
  @visibleForTesting
  Map<String, dynamic> normalizeUserRowForAppMarket(Map<String, dynamic> row) {
    return normalizeAdminUserRowForAppMarket(row);
  }

  List<Map<String, dynamic>> _normalizeCountryReferenceRows(dynamic data) {
    final rows = asListOfMaps(data)
        .map((row) {
          final normalized = Map<String, dynamic>.from(row);
          normalized['supports_momo_code'] =
              row['supports_momo_code'] == true ||
              (row['momo_code_ussd_template']?.toString().trim().isNotEmpty ??
                  false);
          return normalized;
        })
        .toList(growable: false);
    rows.sort(_compareCountryRows);
    return rows;
  }

  List<Map<String, dynamic>> _catalogCountryReferenceRows() {
    final rows = CoolCountryCatalog.all
        .map(
          (country) => <String, dynamic>{
            'iso_code': country.isoCode,
            'country_name': country.name,
            'flag_emoji': country.flagEmoji,
            'dial_code': country.dialCode,
            'currency_code': country.currencyCode,
            'currency_name': country.currencyName,
            'momo_provider_id': country.providerId,
            'country_aliases': country.aliases,
            'momo_provider_aliases': country.providerAliases,
            'mobile_national_number_pattern':
                country.mobileNationalNumberPattern,
            'mobile_possible_lengths': country.mobilePossibleLengths,
            'mobile_example_national': country.mobileExampleNational,
            'mobile_example_e164': country.mobileExampleE164,
            'momo_number_local_pattern': country.momoNumberLocalPattern,
            'momo_number_e164_pattern': country.momoNumberE164Pattern,
            'momo_number_ussd_template': country.momoUssdTemplate,
            'momo_number_ussd_regex': country.momoNumberUssdRegex,
            'momo_number_ussd_example': country.momoNumberUssdExample,
            'momo_code_kind': country.momoCodeKind,
            'momo_code_pattern': country.momoCodePattern,
            'momo_code_min_length': country.momoCodeMinLength,
            'momo_code_max_length': country.momoCodeMaxLength,
            'momo_code_example': country.momoCodeExample,
            'momo_code_ussd_template': country.momoCodeUssdTemplate,
            'momo_code_ussd_regex': country.momoCodeUssdRegex,
            'momo_code_ussd_example': country.momoCodeUssdExample,
            'supports_momo_code': country.supportsMomoCode,
            'phone_validation_source': country.phoneValidationSource,
            'momo_ussd_source': country.momoUssdSource,
            'validation_notes': country.validationNotes,
            'default_lat': null,
            'default_lng': null,
            'sort_order': null,
            'is_active': true,
            'updated_at': null,
          },
        )
        .toList(growable: false);
    rows.sort(_compareCountryRows);
    return rows;
  }

  int _compareCountryRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sortOrderComparison = _sortOrder(a).compareTo(_sortOrder(b));
    if (sortOrderComparison != 0) {
      return sortOrderComparison;
    }

    return (a['country_name']?.toString() ?? '').compareTo(
      b['country_name']?.toString() ?? '',
    );
  }

  int _sortOrder(Map<String, dynamic> row) {
    final value = row['sort_order'];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 1 << 20;
  }
}
