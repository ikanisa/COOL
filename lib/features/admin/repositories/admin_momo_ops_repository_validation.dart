part of 'admin_momo_ops_repository.dart';

extension _AdminMomoOpsValidation on AdminMomoOpsRepository {
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
