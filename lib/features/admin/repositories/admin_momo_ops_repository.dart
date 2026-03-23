import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import 'admin_repository_helpers.dart';

/// Admin repository for MoMo operational views: sender inventory, operational
/// summary, manual review queue, health events, and MoMo validation.
class AdminMomoOpsRepository with AdminRepositoryHelpers {
  AdminMomoOpsRepository({required SupabaseClient client}) : _client = client;

  final SupabaseClient _client;

  @override
  SupabaseClient get client => _client;

  // ── MoMo SMS Operational Summary ──────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoSmsOperationalSummary() async {
    final data = await _client.rpc('get_momo_sms_operational_summary');
    return asListOfMaps(data);
  }

  // ── MoMo SMS Sender Inventory ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoSmsSenderInventory({
    int limit = 20,
    bool includeApproved = false,
  }) async {
    final data = await _client.rpc(
      'get_momo_sms_sender_inventory',
      params: <String, dynamic>{
        'p_limit': limit,
        'p_include_approved': includeApproved,
      },
    );
    return asListOfMaps(data);
  }

  Future<void> acknowledgeMomoSmsSenderInventory({
    required String senderToken,
    String? note,
  }) async {
    await _client.rpc(
      'admin_acknowledge_momo_sms_sender_inventory',
      params: <String, dynamic>{
        'p_sender_token': senderToken,
        'p_note': trimmed(note),
      },
    );
  }

  Future<int> acknowledgeMomoSmsSenderInventoryBatch({
    required List<String> senderTokens,
    String? note,
  }) async {
    if (senderTokens.isEmpty) {
      return 0;
    }

    final data = await _client.rpc(
      'admin_acknowledge_momo_sms_sender_inventory_batch',
      params: <String, dynamic>{
        'p_sender_tokens': senderTokens,
        'p_note': trimmed(note),
      },
    );
    final rows = asListOfMaps(data);
    if (rows.isEmpty) {
      return 0;
    }
    return asInt(rows.first['acknowledged_count']);
  }

  // ── MoMo SMS Manual Review Queue ──────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoSmsManualReviewQueue({
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await _client.rpc(
      'get_momo_sms_manual_review_queue',
      params: <String, dynamic>{'p_limit': limit, 'p_offset': offset},
    );
    return asListOfMaps(data);
  }

  Future<void> rejectMomoSmsManualReview({
    required String reviewId,
    String? note,
  }) async {
    await _client.rpc(
      'admin_reject_momo_sms_manual_review',
      params: <String, dynamic>{
        'p_review_id': reviewId,
        'p_note': trimmed(note),
      },
    );
  }

  Future<int> rejectMomoSmsManualReviewBatch({
    required List<String> reviewIds,
    String? note,
  }) async {
    if (reviewIds.isEmpty) {
      return 0;
    }

    final data = await _client.rpc(
      'admin_reject_momo_sms_manual_review_batch',
      params: <String, dynamic>{
        'p_review_ids': reviewIds,
        'p_note': trimmed(note),
      },
    );
    final rows = asListOfMaps(data);
    if (rows.isEmpty) {
      return 0;
    }
    return asInt(rows.first['rejected_count']);
  }

  // ── Health Events ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchRecentOperationalHealthEvents({
    int limit = 40,
  }) async {
    final data = await _client.rpc(
      'get_recent_operational_health_events',
      params: <String, dynamic>{'p_limit': limit},
    );
    return asListOfMaps(data);
  }

  // ── MoMo Validation Issues ────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMomoValidationIssues() async {
    try {
      final data = await _client.rpc('get_momo_validation_issues');
      return _normalizeIssueRows(data);
    } on PostgrestException catch (error) {
      if (!isMissingSchemaObjectError(error)) {
        rethrow;
      }
    }

    try {
      return await _deriveMomoValidationIssuesLocally();
    } on PostgrestException catch (error) {
      if (!isMissingSchemaObjectError(error)) {
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
      if (!isMissingSchemaObjectError(error)) {
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

  // ── Private helpers ───────────────────────────────────────────────────

  List<Map<String, dynamic>> _normalizeIssueRows(dynamic data) {
    return asListOfMaps(data)
        .map(
          (row) => <String, dynamic>{
            ...row,
            'repair_supported': row['repair_supported'] ?? true,
          },
        )
        .toList(growable: false);
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
    final normalized = trimmed(value)?.toLowerCase();
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
    final trimmedVal = value.trim();
    if (trimmedVal.isEmpty) {
      return 'phone_number';
    }

    final isPhoneNumber = country.isValidPhoneNumber(trimmedVal);
    final isMerchantCode =
        country.supportsMomoCode && country.isValidMerchantCode(trimmedVal);

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

    final digits = trimmedVal.replaceAll(RegExp(r'[^0-9]'), '');
    final dialDigits = country.dialCode.replaceFirst('+', '');

    if (trimmedVal.startsWith('+') ||
        trimmedVal.startsWith('0') ||
        digits.startsWith(dialDigits) ||
        digits.length >= 9) {
      return 'phone_number';
    }

    return 'code';
  }

  Future<List<Map<String, dynamic>>>
  _deriveMomoValidationIssuesLocally() async {
    // Fetch countries for validation.
    final countryData = await _client
        .from('supported_country_momo_reference')
        .select()
        .order('sort_order', ascending: true)
        .order('country_name', ascending: true);
    final activeCountries = asListOfMaps(countryData)
        .where((row) => row['is_active'] == true)
        .map(CoolCountry.fromJson)
        .toList(growable: false);

    final users = asListOfMaps(
      await _client.from('users').select('id, country, momo_number, momo_code'),
    );
    final groups = asListOfMaps(
      await _client
          .from('groups')
          .select(
            'id, type, country, momo_number, receiving_momo_code, '
            'receiving_momo_route_type',
          ),
    );

    final issues = <Map<String, dynamic>>[];

    for (final user in users) {
      final rawCountry = trimmed(user['country']);
      final country = _resolveCountry(rawCountry, source: activeCountries);
      final momoNumber = trimmed(user['momo_number']);
      final momoCode = trimmed(user['momo_code']);

      if (country == null) {
        issues.add(
          _issueRow(
            recordType: 'user',
            recordId: user['id']?.toString() ?? '',
            country: rawCountry,
            issueCode: 'unsupported_country',
            issueMessage:
                'User country ${rawCountry ?? '(blank)'} is not the supported Rwanda market.',
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
      final rawCountry = trimmed(group['country']);
      final country = _resolveCountry(rawCountry, source: activeCountries);
      final groupType = trimmed(group['type'])?.toLowerCase();
      final routeType = _normalizedRouteType(
        group['receiving_momo_route_type'],
      );
      final momoNumber = trimmed(group['momo_number']);
      final momoCode = trimmed(group['receiving_momo_code']);
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
                'Group country ${rawCountry ?? '(blank)'} is not the supported Rwanda market.',
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
}
