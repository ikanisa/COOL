import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';

/// Central repository for admin CRUD operations across all dynamic content tables.
class AdminRepository {
  AdminRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
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

  Future<List<Map<String, dynamic>>> fetchPartners({String? country}) async {
    var query = _client.from('partners').select();
    final normalizedCountry = _normalizeCountryOrNull(country);
    if (normalizedCountry != null) {
      query = query.eq('country', normalizedCountry);
    }
    final data = await query
        .order('country', ascending: true)
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertPartner(Map<String, dynamic> partner) async {
    await _client
        .from('partners')
        .upsert(_withNormalizedCountry(partner, required: true));
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
    String? country,
  }) async {
    var query = _client
        .from('partner_services')
        .select('*, partners!inner(name, slug)');
    if (partnerId != null) {
      query = query.eq('partner_id', partnerId);
    }
    final normalizedCountry = _normalizeCountryOrNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }
    final data = await query
        .order('country', ascending: true)
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertPartnerService(Map<String, dynamic> service) async {
    final normalizedService = await _withServiceCountryFromPartner(service);
    await _client.from('partner_services').upsert(normalizedService);
  }

  Future<void> deletePartnerService(String id) async {
    await _client.from('partner_services').delete().eq('id', id);
  }

  // ── Quick Actions ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchQuickActions({
    String? country,
  }) async {
    var query = _client.from('quick_actions').select();
    final normalizedCountry = _normalizeCountryOrNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }
    final data = await query
        .order('country', ascending: true)
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertQuickAction(Map<String, dynamic> action) async {
    await _client.from('quick_actions').upsert(_withNormalizedCountry(action));
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

  Future<List<Map<String, dynamic>>> fetchVehicleTypes({
    String? country,
  }) async {
    var query = _client.from('vehicle_types').select();
    final normalizedCountry = _normalizeCountryOrNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }
    final data = await query
        .order('country', ascending: true)
        .order('sort_order', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertVehicleType(Map<String, dynamic> type) async {
    await _client.from('vehicle_types').upsert(_withNormalizedCountry(type));
  }

  Future<void> deleteVehicleType(String id) async {
    await _client.from('vehicle_types').delete().eq('id', id);
  }

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
      if (!_isMissingSchemaObjectError(error)) {
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
      if (!_isMissingSchemaObjectError(error)) {
        rethrow;
      }
    } catch (_) {
      return _catalogCountryReferenceRows();
    }

    return _catalogCountryReferenceRows();
  }

  Future<List<Map<String, dynamic>>> fetchMomoValidationIssues() async {
    try {
      final data = await _client.rpc('get_momo_validation_issues');
      return _normalizeIssueRows(data);
    } on PostgrestException catch (error) {
      if (!_isMissingSchemaObjectError(error)) {
        rethrow;
      }
    }

    try {
      return await _deriveMomoValidationIssuesLocally();
    } on PostgrestException catch (error) {
      if (!_isMissingSchemaObjectError(error)) {
        rethrow;
      }
    } catch (_) {
      // Fall through to a synthetic compatibility issue row.
    }

    return <Map<String, dynamic>>[
      _issueRow(
        recordType: 'system',
        recordId: 'legacy-schema',
        issueCode: 'validation_backend_unavailable',
        issueMessage:
            'This backend is missing the tables or columns required to audit MoMo validation issues. Apply the latest compatibility migration to enable server-side validation diagnostics.',
      ),
    ];
  }

  Future<Map<String, dynamic>> repairMomoValidationIssue({
    required String recordType,
    required String recordId,
    required String issueCode,
  }) async {
    dynamic data;
    try {
      data = await _client.rpc(
        'repair_momo_validation_issue',
        params: <String, dynamic>{
          'p_record_type': recordType,
          'p_record_id': recordId,
          'p_issue_code': issueCode,
        },
      );
    } on PostgrestException catch (error) {
      if (!_isMissingSchemaObjectError(error)) {
        rethrow;
      }
      return <String, dynamic>{
        'status': 'unavailable',
        'record_type': recordType,
        'record_id': recordId,
        'issue_code': issueCode,
        'message':
            'Repair tools are unavailable on this backend until the compatibility migration is applied.',
      };
    }

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

  Future<List<Map<String, dynamic>>> fetchAppConfig({String? country}) async {
    var query = _client.from('app_config').select();
    final normalizedCountry = _normalizeCountryOrNull(country);
    if (normalizedCountry != null) {
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }
    final data = await query
        .order('country', ascending: true)
        .order('key', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> upsertAppConfig(Map<String, dynamic> config) async {
    await _client.from('app_config').upsert(_withNormalizedCountry(config));
  }

  Future<void> upsertAppConfigs(List<Map<String, dynamic>> configs) async {
    if (configs.isEmpty) {
      return;
    }
    await _client
        .from('app_config')
        .upsert(configs.map(_withNormalizedCountry).toList(growable: false));
  }

  Future<void> deleteAppConfig(String key) async {
    await _client.from('app_config').delete().eq('key', key);
  }

  Future<List<Map<String, dynamic>>>
  _deriveMomoValidationIssuesLocally() async {
    final countryRows = await fetchCountries();
    final activeCountries = countryRows
        .where((row) => row['is_active'] == true)
        .map(CoolCountry.fromJson)
        .toList(growable: false);

    final users = _asListOfMaps(
      await _client.from('users').select('id, country, momo_number, momo_code'),
    );
    final groups = _asListOfMaps(
      await _client
          .from('groups')
          .select(
            'id, type, country, momo_number, receiving_momo_code, '
            'receiving_momo_route_type',
          ),
    );

    final issues = <Map<String, dynamic>>[];

    for (final user in users) {
      final rawCountry = _trimmed(user['country']);
      final country = _resolveCountry(rawCountry, source: activeCountries);
      final momoNumber = _trimmed(user['momo_number']);
      final momoCode = _trimmed(user['momo_code']);

      if (country == null) {
        issues.add(
          _issueRow(
            recordType: 'user',
            recordId: user['id']?.toString() ?? '',
            country: rawCountry,
            issueCode: 'unsupported_country',
            issueMessage:
                'User country ${rawCountry ?? '(blank)'} is not configured in supported_countries.',
            momoNumber: momoNumber,
            momoCode: momoCode,
          ),
        );
        continue;
      }

      if (momoNumber != null && !country.isValidPhoneNumber(momoNumber)) {
        issues.add(
          _issueRow(
            recordType: 'user',
            recordId: user['id']?.toString() ?? '',
            country: rawCountry,
            countryName: country.name,
            issueCode: 'invalid_momo_number',
            issueMessage: 'User MoMo number is invalid for ${country.name}.',
            momoNumber: momoNumber,
            momoCode: momoCode,
            expectedPhoneExample: country.mobileExampleE164,
            expectedCodeExample: country.momoCodeExample,
            phoneUssdExample: country.momoNumberUssdExample,
            codeUssdExample: country.momoCodeUssdExample,
          ),
        );
      }

      if (momoCode != null && !country.isValidMerchantCode(momoCode)) {
        issues.add(
          _issueRow(
            recordType: 'user',
            recordId: user['id']?.toString() ?? '',
            country: rawCountry,
            countryName: country.name,
            issueCode: 'invalid_momo_code',
            issueMessage:
                'User merchant code is invalid or unsupported for ${country.name}.',
            momoNumber: momoNumber,
            momoCode: momoCode,
            expectedPhoneExample: country.mobileExampleE164,
            expectedCodeExample: country.momoCodeExample,
            phoneUssdExample: country.momoNumberUssdExample,
            codeUssdExample: country.momoCodeUssdExample,
          ),
        );
      }
    }

    for (final group in groups) {
      final rawCountry = _trimmed(group['country']);
      final country = _resolveCountry(rawCountry, source: activeCountries);
      final groupType = _trimmed(group['type'])?.toLowerCase();
      final routeType = _normalizedRouteType(
        group['receiving_momo_route_type'],
      );
      final momoNumber = _trimmed(group['momo_number']);
      final momoCode = _trimmed(group['receiving_momo_code']);
      final effectiveRecipient = momoCode ?? momoNumber;
      final effectiveRouteType =
          routeType ??
          (effectiveRecipient == null || country == null
              ? null
              : _inferRecipientType(country, effectiveRecipient));

      if (country == null) {
        issues.add(
          _issueRow(
            recordType: 'group',
            recordId: group['id']?.toString() ?? '',
            country: rawCountry,
            routeType: routeType,
            issueCode: 'unsupported_country',
            issueMessage:
                'Group country ${rawCountry ?? '(blank)'} is not configured in supported_countries.',
            momoNumber: momoNumber,
            momoCode: momoCode,
          ),
        );
        continue;
      }

      if (groupType == 'community' && effectiveRecipient == null) {
        issues.add(
          _issueRow(
            recordType: 'group',
            recordId: group['id']?.toString() ?? '',
            country: rawCountry,
            countryName: country.name,
            routeType: routeType,
            issueCode: 'missing_community_recipient',
            issueMessage:
                'Community group is missing both MoMo number and merchant-code recipient.',
            momoNumber: momoNumber,
            momoCode: momoCode,
            expectedPhoneExample: country.mobileExampleE164,
            expectedCodeExample: country.momoCodeExample,
            phoneUssdExample: country.momoNumberUssdExample,
            codeUssdExample: country.momoCodeUssdExample,
          ),
        );
      }

      if (routeType != null &&
          routeType != 'phone_number' &&
          routeType != 'code') {
        issues.add(
          _issueRow(
            recordType: 'group',
            recordId: group['id']?.toString() ?? '',
            country: rawCountry,
            countryName: country.name,
            routeType: routeType,
            issueCode: 'unsupported_route_type',
            issueMessage:
                'Group route type $routeType must be phone_number or code.',
            momoNumber: momoNumber,
            momoCode: momoCode,
            expectedPhoneExample: country.mobileExampleE164,
            expectedCodeExample: country.momoCodeExample,
            phoneUssdExample: country.momoNumberUssdExample,
            codeUssdExample: country.momoCodeUssdExample,
          ),
        );
      }

      if (effectiveRecipient == null || effectiveRouteType == null) {
        continue;
      }

      if (effectiveRouteType == 'phone_number' &&
          !country.isValidPhoneNumber(effectiveRecipient)) {
        issues.add(
          _issueRow(
            recordType: 'group',
            recordId: group['id']?.toString() ?? '',
            country: rawCountry,
            countryName: country.name,
            routeType: effectiveRouteType,
            issueCode: 'invalid_phone_recipient',
            issueMessage:
                'Group phone-number recipient is invalid for ${country.name}.',
            momoNumber: momoNumber,
            momoCode: momoCode,
            expectedPhoneExample: country.mobileExampleE164,
            expectedCodeExample: country.momoCodeExample,
            phoneUssdExample: country.momoNumberUssdExample,
            codeUssdExample: country.momoCodeUssdExample,
          ),
        );
      }

      if (effectiveRouteType == 'code' &&
          !country.isValidMerchantCode(effectiveRecipient)) {
        issues.add(
          _issueRow(
            recordType: 'group',
            recordId: group['id']?.toString() ?? '',
            country: rawCountry,
            countryName: country.name,
            routeType: effectiveRouteType,
            issueCode: 'invalid_momo_code',
            issueMessage:
                'Group merchant-code recipient is invalid or unsupported for ${country.name}.',
            momoNumber: momoNumber,
            momoCode: momoCode,
            expectedPhoneExample: country.mobileExampleE164,
            expectedCodeExample: country.momoCodeExample,
            phoneUssdExample: country.momoNumberUssdExample,
            codeUssdExample: country.momoCodeUssdExample,
          ),
        );
      }
    }

    issues.sort((a, b) {
      final issueComparison = (a['issue_code']?.toString() ?? '').compareTo(
        b['issue_code']?.toString() ?? '',
      );
      if (issueComparison != 0) {
        return issueComparison;
      }

      final countryComparison = (a['country']?.toString() ?? '').compareTo(
        b['country']?.toString() ?? '',
      );
      if (countryComparison != 0) {
        return countryComparison;
      }

      final typeComparison = (a['record_type']?.toString() ?? '').compareTo(
        b['record_type']?.toString() ?? '',
      );
      if (typeComparison != 0) {
        return typeComparison;
      }

      return (a['record_id']?.toString() ?? '').compareTo(
        b['record_id']?.toString() ?? '',
      );
    });

    return issues;
  }

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

  Future<Map<String, dynamic>> _withServiceCountryFromPartner(
    Map<String, dynamic> service,
  ) async {
    final normalized = Map<String, dynamic>.from(
      _withNormalizedCountry(service),
    );
    final partnerId = normalized['partner_id']?.toString().trim();
    if (partnerId == null || partnerId.isEmpty) {
      throw StateError('Partner selection is required for partner services.');
    }

    final partnerRows = await _client
        .from('partners')
        .select('country')
        .eq('id', partnerId)
        .limit(1);
    if (partnerRows.isEmpty) {
      throw StateError('Selected partner could not be found.');
    }

    final partnerCountry = _normalizeCountryOrNull(
      partnerRows.first['country']?.toString(),
    );
    if (partnerCountry == null) {
      throw StateError('Selected partner does not have a valid country.');
    }

    normalized['country'] = partnerCountry;
    return normalized;
  }

  List<Map<String, dynamic>> _normalizeCountryReferenceRows(dynamic data) {
    final rows = _asListOfMaps(data)
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

  List<Map<String, dynamic>> _normalizeIssueRows(dynamic data) {
    return _asListOfMaps(data)
        .map(
          (row) => <String, dynamic>{
            ...row,
            'repair_supported': row['repair_supported'] ?? true,
          },
        )
        .toList(growable: false);
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

  CoolCountry? _resolveCountry(
    String? rawCountry, {
    required Iterable<CoolCountry> source,
  }) {
    if (rawCountry == null || rawCountry.trim().isEmpty) {
      return null;
    }

    return CoolCountryCatalog.byIsoCode(rawCountry, source: source) ??
        CoolCountryCatalog.byDialCode(rawCountry, source: source) ??
        CoolCountryCatalog.fromPhoneNumber(rawCountry, source: source);
  }

  Map<String, dynamic> _issueRow({
    required String recordType,
    required String recordId,
    required String issueCode,
    required String issueMessage,
    String? country,
    String? countryName,
    String? routeType,
    String? momoNumber,
    String? momoCode,
    String? expectedPhoneExample,
    String? expectedCodeExample,
    String? phoneUssdExample,
    String? codeUssdExample,
  }) {
    return <String, dynamic>{
      'record_type': recordType,
      'record_id': recordId,
      'country': country,
      'country_name': countryName,
      'route_type': routeType,
      'issue_code': issueCode,
      'issue_message': issueMessage,
      'momo_number': momoNumber,
      'momo_code': momoCode,
      'expected_phone_example': expectedPhoneExample,
      'expected_code_example': expectedCodeExample,
      'phone_ussd_example': phoneUssdExample,
      'code_ussd_example': codeUssdExample,
      'repair_supported': false,
    };
  }

  String? _normalizedRouteType(dynamic value) {
    final normalized = _trimmed(value)?.toLowerCase();
    switch (normalized) {
      case 'phone':
      case 'phone_number':
      case 'number':
        return 'phone_number';
      case 'code':
      case 'merchant_code':
        return 'code';
      default:
        return normalized;
    }
  }

  String _inferRecipientType(CoolCountry country, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'phone_number';
    }

    final isPhoneNumber = country.isValidPhoneNumber(trimmed);
    final isMerchantCode =
        country.supportsMomoCode && country.isValidMerchantCode(trimmed);

    if (isPhoneNumber && !isMerchantCode) {
      return 'phone_number';
    }
    if (isMerchantCode && !isPhoneNumber) {
      return 'code';
    }
    if (isPhoneNumber) {
      return 'phone_number';
    }
    if (isMerchantCode) {
      return 'code';
    }

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    final dialDigits = country.dialCode.replaceFirst('+', '');

    if (trimmed.startsWith('+') ||
        trimmed.startsWith('0') ||
        digits.startsWith(dialDigits) ||
        digits.length >= 9) {
      return 'phone_number';
    }

    return 'code';
  }

  bool _isMissingSchemaObjectError(PostgrestException error) {
    final normalizedMessage = error.message.toLowerCase();
    return error.code == 'PGRST202' ||
        error.code == 'PGRST205' ||
        normalizedMessage.contains('does not exist') ||
        normalizedMessage.contains('could not find') ||
        normalizedMessage.contains('missing table') ||
        normalizedMessage.contains('missing function');
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

  List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }

    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String? _trimmed(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') {
      return null;
    }
    return text;
  }
}
