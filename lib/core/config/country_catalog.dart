enum MomoRecipientType { phoneNumber, code }

class CoolCountry {
  const CoolCountry({
    required this.isoCode,
    required this.dialCode,
    required this.name,
    required this.flagEmoji,
    required this.currencyCode,
    required this.currencyName,
    required this.momoUssdTemplate,
    this.momoCodeUssdTemplate,
    this.providerIdValue,
    this.aliases = const <String>[],
    this.providerAliases = const <String>[],
    this.mobileNationalNumberPattern,
    this.mobilePossibleLengths = const <int>[],
    this.mobileExampleNational,
    this.mobileExampleE164,
    this.momoNumberLocalPattern,
    this.momoNumberE164Pattern,
    this.momoNumberUssdRegex,
    this.momoNumberUssdExample,
    this.momoCodeKind,
    this.momoCodePattern,
    this.momoCodeMinLength,
    this.momoCodeMaxLength,
    this.momoCodeExample,
    this.momoCodeUssdRegex,
    this.momoCodeUssdExample,
    this.phoneValidationSource,
    this.momoUssdSource,
    this.validationNotes,
  });

  final String isoCode;
  final String dialCode;
  final String name;
  final String flagEmoji;
  final String currencyCode;
  final String currencyName;
  final String momoUssdTemplate;
  final String? momoCodeUssdTemplate;
  final String? providerIdValue;
  final List<String> aliases;
  final List<String> providerAliases;
  final String? mobileNationalNumberPattern;
  final List<int> mobilePossibleLengths;
  final String? mobileExampleNational;
  final String? mobileExampleE164;
  final String? momoNumberLocalPattern;
  final String? momoNumberE164Pattern;
  final String? momoNumberUssdRegex;
  final String? momoNumberUssdExample;
  final String? momoCodeKind;
  final String? momoCodePattern;
  final int? momoCodeMinLength;
  final int? momoCodeMaxLength;
  final String? momoCodeExample;
  final String? momoCodeUssdRegex;
  final String? momoCodeUssdExample;
  final String? phoneValidationSource;
  final String? momoUssdSource;
  final String? validationNotes;

  String get providerId => providerIdValue ?? 'momo_${isoCode.toLowerCase()}';
  String get displayName => '$flagEmoji $name';
  String get pickerLabel => '$flagEmoji  $name  $dialCode';
  String get routeSummary => '$currencyCode · $dialCode';
  bool get supportsMomoCode => (momoCodeUssdTemplate ?? '').trim().isNotEmpty;

  factory CoolCountry.fromJson(Map<String, dynamic> json) {
    return CoolCountry(
      isoCode: json['iso_code']?.toString() ?? '',
      dialCode: json['dial_code']?.toString() ?? '',
      name:
          json['country_name']?.toString() ??
          json['name']?.toString() ??
          json['display_name']?.toString() ??
          '',
      flagEmoji: json['flag_emoji']?.toString() ?? '',
      currencyCode: json['currency_code']?.toString() ?? '',
      currencyName: json['currency_name']?.toString() ?? '',
      providerIdValue:
          json['momo_provider_id']?.toString() ??
          json['provider_id']?.toString(),
      momoUssdTemplate:
          json['momo_number_ussd_template']?.toString() ??
          json['momo_ussd_template']?.toString() ??
          '',
      momoCodeUssdTemplate:
          json['momo_code_ussd_template']?.toString().trim().isEmpty ?? true
          ? null
          : json['momo_code_ussd_template']?.toString(),
      aliases: _asStringList(json['country_aliases']),
      providerAliases: _asStringList(json['momo_provider_aliases']),
      mobileNationalNumberPattern: json['mobile_national_number_pattern']
          ?.toString(),
      mobilePossibleLengths: _asIntList(json['mobile_possible_lengths']),
      mobileExampleNational: json['mobile_example_national']?.toString(),
      mobileExampleE164: json['mobile_example_e164']?.toString(),
      momoNumberLocalPattern: json['momo_number_local_pattern']?.toString(),
      momoNumberE164Pattern: json['momo_number_e164_pattern']?.toString(),
      momoNumberUssdRegex: json['momo_number_ussd_regex']?.toString(),
      momoNumberUssdExample: json['momo_number_ussd_example']?.toString(),
      momoCodeKind: json['momo_code_kind']?.toString(),
      momoCodePattern: json['momo_code_pattern']?.toString(),
      momoCodeMinLength: _asIntOrNull(json['momo_code_min_length']),
      momoCodeMaxLength: _asIntOrNull(json['momo_code_max_length']),
      momoCodeExample: json['momo_code_example']?.toString(),
      momoCodeUssdRegex: json['momo_code_ussd_regex']?.toString(),
      momoCodeUssdExample: json['momo_code_ussd_example']?.toString(),
      phoneValidationSource: json['phone_validation_source']?.toString(),
      momoUssdSource: json['momo_ussd_source']?.toString(),
      validationNotes: json['validation_notes']?.toString(),
    );
  }

  String buildUssdCode({
    required String recipientMomo,
    required int amount,
    MomoRecipientType recipientType = MomoRecipientType.phoneNumber,
  }) {
    final template = switch (recipientType) {
      MomoRecipientType.phoneNumber => momoUssdTemplate,
      MomoRecipientType.code => momoCodeUssdTemplate,
    };

    if (template == null || template.trim().isEmpty) {
      throw UnsupportedError(
        'No USSD template is configured for $recipientType in $isoCode.',
      );
    }

    final recipient = switch (recipientType) {
      MomoRecipientType.phoneNumber => normalizeLocalPhone(recipientMomo),
      MomoRecipientType.code => normalizeMerchantCode(recipientMomo),
    };

    final ussdCode = template
        .replaceAll('{recipient}', recipient)
        .replaceAll('{amount}', amount.toString());

    final routeRegex = switch (recipientType) {
      MomoRecipientType.phoneNumber => momoNumberUssdRegex,
      MomoRecipientType.code => momoCodeUssdRegex,
    };
    if (routeRegex != null &&
        routeRegex.trim().isNotEmpty &&
        !RegExp(routeRegex).hasMatch(ussdCode)) {
      throw FormatException(
        'The USSD route for $isoCode is invalid for $recipientType.',
      );
    }

    return ussdCode;
  }

  String normalizeLocalPhone(String value) {
    final e164 = buildE164Phone(value);
    var digits = e164.replaceAll(RegExp(r'[^0-9]'), '');
    final dialDigits = dialCode.replaceFirst('+', '');

    if (digits.startsWith(dialDigits)) {
      digits = digits.substring(dialDigits.length);
    }
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    return digits;
  }

  /// Normalize a phone to the user-facing national format used for storage
  /// and profile display. This preserves a leading trunk zero when the
  /// country's national examples use one (for example `078...` in Rwanda).
  String normalizeNationalPhone(String value) {
    final e164 = buildE164Phone(value);
    var digits = e164.replaceAll(RegExp(r'[^0-9]'), '');
    final dialDigits = dialCode.replaceFirst('+', '');

    if (digits.startsWith(dialDigits)) {
      digits = digits.substring(dialDigits.length);
    }

    final nationalExampleDigits = mobileExampleNational?.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    if (nationalExampleDigits != null && nationalExampleDigits.isNotEmpty) {
      if (nationalExampleDigits.startsWith('0')) {
        return digits.startsWith('0') ? digits : '0$digits';
      }

      while (digits.startsWith('0')) {
        digits = digits.substring(1);
      }
      return digits;
    }

    final localPattern = momoNumberLocalPattern ?? mobileNationalNumberPattern;
    if (_matchesPattern(digits, localPattern)) {
      return digits;
    }

    final withLeadingZero = digits.startsWith('0') ? digits : '0$digits';
    if (_matchesPattern(withLeadingZero, localPattern)) {
      return withLeadingZero;
    }

    return digits;
  }

  String normalizeMerchantCode(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      throw const FormatException('Merchant code is required.');
    }
    if (!supportsMomoCode) {
      throw UnsupportedError(
        'Merchant-code payments are not configured for $isoCode.',
      );
    }

    if (momoCodePattern != null &&
        momoCodePattern!.trim().isNotEmpty &&
        !RegExp(momoCodePattern!).hasMatch(digits)) {
      throw FormatException('Enter a valid merchant code for $name.');
    }

    if (momoCodeMinLength != null && digits.length < momoCodeMinLength!) {
      throw FormatException('Merchant code is too short for $name.');
    }
    if (momoCodeMaxLength != null && digits.length > momoCodeMaxLength!) {
      throw FormatException('Merchant code is too long for $name.');
    }

    return digits;
  }

  String buildE164Phone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Phone number is required.');
    }

    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    final plusCandidate = '+$digits';
    final e164Pattern = momoNumberE164Pattern;
    final localPattern = momoNumberLocalPattern ?? mobileNationalNumberPattern;
    final hasValidationMetadata =
        (e164Pattern?.trim().isNotEmpty ?? false) ||
        (localPattern?.trim().isNotEmpty ?? false) ||
        mobilePossibleLengths.isNotEmpty;

    if (!hasValidationMetadata) {
      if (trimmed.startsWith('+')) {
        return plusCandidate;
      }
      return '$dialCode${_fallbackLocalDigits(digits, dialCode)}';
    }

    if (_matchesPattern(plusCandidate, e164Pattern)) {
      return plusCandidate;
    }

    final normalizedLocalDigits = _normalizedLocalDigitsForE164(digits);
    if (normalizedLocalDigits != null) {
      return '$dialCode$normalizedLocalDigits';
    }

    final dialDigits = dialCode.replaceFirst('+', '');
    if (digits.startsWith(dialDigits)) {
      final withPlus = '+$digits';
      if (_matchesPattern(withPlus, e164Pattern)) {
        return withPlus;
      }

      final nationalDigits = digits.substring(dialDigits.length);
      final normalizedNationalDigits = _normalizedLocalDigitsForE164(
        nationalDigits,
      );
      if (normalizedNationalDigits != null) {
        return '$dialCode$normalizedNationalDigits';
      }
    }

    if (mobilePossibleLengths.isNotEmpty &&
        !mobilePossibleLengths.contains(digits.length)) {
      throw FormatException('Enter a valid $name mobile money number.');
    }

    throw FormatException('Enter a valid $name mobile money number.');
  }

  bool isValidPhoneNumber(String value) {
    try {
      buildE164Phone(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool isValidMerchantCode(String value) {
    try {
      normalizeMerchantCode(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  String phoneExampleHint() {
    return mobileExampleNational?.trim().isNotEmpty ?? false
        ? mobileExampleNational!.trim()
        : '$dialCode 91234567';
  }

  String? _normalizedLocalDigitsForE164(String digits) {
    final localPattern = momoNumberLocalPattern ?? mobileNationalNumberPattern;
    if (!_matchesPattern(digits, localPattern)) {
      return null;
    }

    var normalized = digits;
    if (!_e164KeepsLeadingZero() && normalized.startsWith('0')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  bool _e164KeepsLeadingZero() {
    final exampleDigits = mobileExampleE164?.replaceAll(RegExp(r'[^0-9]'), '');
    if (exampleDigits == null || exampleDigits.isEmpty) {
      return false;
    }

    final dialDigits = dialCode.replaceFirst('+', '');
    if (!exampleDigits.startsWith(dialDigits) ||
        exampleDigits.length <= dialDigits.length) {
      return false;
    }

    return exampleDigits.substring(dialDigits.length).startsWith('0');
  }
}

String _fallbackLocalDigits(String digits, String dialCode) {
  var normalized = digits;
  final dialDigits = dialCode.replaceFirst('+', '');
  if (normalized.startsWith(dialDigits)) {
    normalized = normalized.substring(dialDigits.length);
  }
  while (normalized.startsWith('0')) {
    normalized = normalized.substring(1);
  }
  return normalized;
}

bool _matchesPattern(String value, String? pattern) {
  if (pattern == null || pattern.trim().isEmpty) {
    return false;
  }
  return RegExp(pattern).hasMatch(value);
}

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value
        .whereType<Object>()
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

List<int> _asIntList(dynamic value) {
  if (value is List) {
    return value.map(_asIntOrNull).whereType<int>().toList(growable: false);
  }
  return const <int>[];
}

int? _asIntOrNull(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

abstract final class CoolCountryCatalog {
  static const List<CoolCountry> all = <CoolCountry>[
    CoolCountry(
      isoCode: 'BJ',
      dialCode: '+229',
      name: 'Benin',
      flagEmoji: '🇧🇯',
      currencyCode: 'XOF',
      currencyName: 'West African CFA franc',
      momoUssdTemplate: '*400*1*{recipient}*{amount}#',
      aliases: <String>['Benin'],
      mobileNationalNumberPattern: r'^0?[1-9]\d{7,8}$',
      mobilePossibleLengths: <int>[8, 9, 10],
      mobileExampleNational: '0195123456',
      mobileExampleE164: '+2290195123456',
      momoNumberLocalPattern: r'^0?[1-9]\d{7,8}$',
      momoNumberE164Pattern: r'^\+2290?[1-9]\d{7,8}$',
    ),
    CoolCountry(
      isoCode: 'BW',
      dialCode: '+267',
      name: 'Botswana',
      flagEmoji: '🇧🇼',
      currencyCode: 'BWP',
      currencyName: 'Botswana pula',
      momoUssdTemplate: '*167*1*{recipient}*{amount}#',
      aliases: <String>['Botswana'],
      mobileNationalNumberPattern: r'^7[1-8]\d{6}$',
      mobilePossibleLengths: <int>[8],
      mobileExampleNational: '71123456',
      mobileExampleE164: '+26771123456',
      momoNumberLocalPattern: r'^7[1-8]\d{6}$',
      momoNumberE164Pattern: r'^\+2677[1-8]\d{6}$',
      phoneValidationSource: 'ITU E.164 / BOCRA Botswana',
    ),
    CoolCountry(
      isoCode: 'CM',
      dialCode: '+237',
      name: 'Cameroon',
      flagEmoji: '🇨🇲',
      currencyCode: 'XAF',
      currencyName: 'Central African CFA franc',
      momoUssdTemplate: '*126*1*{recipient}*{amount}#',
      aliases: <String>['Cameroon'],
      mobileNationalNumberPattern: r'^[26]\d{7,8}$',
      mobilePossibleLengths: <int>[8, 9],
      mobileExampleNational: '671234567',
      mobileExampleE164: '+237671234567',
      momoNumberLocalPattern: r'^[26]\d{7,8}$',
      momoNumberE164Pattern: r'^\+237[26]\d{7,8}$',
      phoneValidationSource: 'ITU E.164 / GSMA',
    ),
    CoolCountry(
      isoCode: 'CG',
      dialCode: '+242',
      name: 'Congo Brazzaville',
      flagEmoji: '🇨🇬',
      currencyCode: 'XAF',
      currencyName: 'Central African CFA franc',
      momoUssdTemplate: '*124*1*{recipient}*{amount}#',
      aliases: <String>[
        'Congo Brazzaville',
        'Republic of the Congo',
        'Republic of Congo',
        'Congo',
      ],
      mobileNationalNumberPattern: r'^0?[56]\d{7}$',
      mobilePossibleLengths: <int>[8, 9],
      mobileExampleNational: '061234567',
      mobileExampleE164: '+24261234567',
      momoNumberLocalPattern: r'^0?[56]\d{7}$',
      momoNumberE164Pattern: r'^\+242[56]\d{7}$',
      phoneValidationSource: 'ITU E.164 / ARPCE Congo',
    ),
    CoolCountry(
      isoCode: 'CI',
      dialCode: '+225',
      name: "Cote d'Ivoire",
      flagEmoji: '🇨🇮',
      currencyCode: 'XOF',
      currencyName: 'West African CFA franc',
      momoUssdTemplate: '*133*1*{recipient}*{amount}#',
      aliases: <String>["Cote d'Ivoire", "Côte d'Ivoire", 'Ivory Coast'],
      mobileNationalNumberPattern: r'^0?[027]\d{8}$',
      mobilePossibleLengths: <int>[10],
      mobileExampleNational: '0710345678',
      mobileExampleE164: '+225710345678',
      momoNumberLocalPattern: r'^0?[027]\d{8}$',
      momoNumberE164Pattern: r'^\+225[027]\d{8}$',
      phoneValidationSource: 'ITU E.164 / ARTCI',
    ),
    CoolCountry(
      isoCode: 'GH',
      dialCode: '+233',
      name: 'Ghana',
      flagEmoji: '🇬🇭',
      currencyCode: 'GHS',
      currencyName: 'Ghanaian cedi',
      momoUssdTemplate: '*170*1*{recipient}*{amount}#',
      aliases: <String>['Ghana'],
      providerAliases: <String>['mtn_ghana', 'mtn', 'vodafone', 'airteltigo'],
      mobileNationalNumberPattern: r'^0?[235]\d{8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0231234567',
      mobileExampleE164: '+233231234567',
      momoNumberLocalPattern: r'^0?[235]\d{8}$',
      momoNumberE164Pattern: r'^\+233[235]\d{8}$',
      phoneValidationSource: 'ITU E.164 / NCA Ghana',
    ),
    CoolCountry(
      isoCode: 'GN',
      dialCode: '+224',
      name: 'Guinea',
      flagEmoji: '🇬🇳',
      currencyCode: 'GNF',
      currencyName: 'Guinean franc',
      momoUssdTemplate: '*155*1*{recipient}*{amount}#',
      aliases: <String>['Guinea'],
      mobileNationalNumberPattern: r'^[67]\d{8}$',
      mobilePossibleLengths: <int>[9],
      mobileExampleNational: '621234567',
      mobileExampleE164: '+224621234567',
      momoNumberLocalPattern: r'^[67]\d{8}$',
      momoNumberE164Pattern: r'^\+224[67]\d{8}$',
      phoneValidationSource: 'ITU E.164 / ARPT Guinea',
    ),
    CoolCountry(
      isoCode: 'GW',
      dialCode: '+245',
      name: 'Guinea-Bissau',
      flagEmoji: '🇬🇼',
      currencyCode: 'XOF',
      currencyName: 'West African CFA franc',
      momoUssdTemplate: '*124*1*{recipient}*{amount}#',
      aliases: <String>['Guinea-Bissau', 'Guinea Bissau'],
      mobileNationalNumberPattern: r'^[5-7]\d{6}$',
      mobilePossibleLengths: <int>[7],
      mobileExampleNational: '5551234',
      mobileExampleE164: '+2455551234',
      momoNumberLocalPattern: r'^[5-7]\d{6}$',
      momoNumberE164Pattern: r'^\+245[5-7]\d{6}$',
      phoneValidationSource: 'ITU E.164 / ARN Guinea-Bissau',
    ),
    CoolCountry(
      isoCode: 'KE',
      dialCode: '+254',
      name: 'Kenya',
      flagEmoji: '🇰🇪',
      currencyCode: 'KES',
      currencyName: 'Kenyan shilling',
      momoUssdTemplate: '*334*1*{recipient}*{amount}#',
      aliases: <String>['Kenya'],
      providerAliases: <String>['mpesa', 'm-pesa', 'safaricom'],
      mobileNationalNumberPattern: r'^0?[17]\d{8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0712345678',
      mobileExampleE164: '+254712345678',
      momoNumberLocalPattern: r'^0?[17]\d{8}$',
      momoNumberE164Pattern: r'^\+254[17]\d{8}$',
      phoneValidationSource: 'ITU E.164 / CA Kenya',
    ),
    CoolCountry(
      isoCode: 'LR',
      dialCode: '+231',
      name: 'Liberia',
      flagEmoji: '🇱🇷',
      currencyCode: 'LRD',
      currencyName: 'Liberian dollar',
      momoUssdTemplate: '*156*1*{recipient}*{amount}#',
      aliases: <String>['Liberia'],
      mobileNationalNumberPattern: r'^0?(?:555|77[025-9]|88[01678])\d{6}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0770123456',
      mobileExampleE164: '+231770123456',
      momoNumberLocalPattern: r'^0?(?:555|77[025-9]|88[01678])\d{6}$',
      momoNumberE164Pattern: r'^\+231(?:555|77[025-9]|88[01678])\d{6}$',
      phoneValidationSource:
          'LTA Liberia national numbering plan (July 18, 2024) / ITU E.164',
    ),
    CoolCountry(
      isoCode: 'MW',
      dialCode: '+265',
      name: 'Malawi',
      flagEmoji: '🇲🇼',
      currencyCode: 'MWK',
      currencyName: 'Malawian kwacha',
      momoUssdTemplate: '*444*1*{recipient}*{amount}#',
      aliases: <String>['Malawi'],
      mobileNationalNumberPattern: r'^0?[89]\d{8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0991234567',
      mobileExampleE164: '+265991234567',
      momoNumberLocalPattern: r'^0?[89]\d{8}$',
      momoNumberE164Pattern: r'^\+265[89]\d{8}$',
      phoneValidationSource: 'ITU E.164 / MACRA Malawi',
    ),
    CoolCountry(
      isoCode: 'MZ',
      dialCode: '+258',
      name: 'Mozambique',
      flagEmoji: '🇲🇿',
      currencyCode: 'MZN',
      currencyName: 'Mozambican metical',
      momoUssdTemplate: '*197*1*{recipient}*{amount}#',
      aliases: <String>['Mozambique'],
      mobileNationalNumberPattern: r'^[89]\d{8}$',
      mobilePossibleLengths: <int>[9],
      mobileExampleNational: '821234567',
      mobileExampleE164: '+258821234567',
      momoNumberLocalPattern: r'^[89]\d{8}$',
      momoNumberE164Pattern: r'^\+258[89]\d{8}$',
      phoneValidationSource: 'ITU E.164 / INCM Mozambique',
    ),
    CoolCountry(
      isoCode: 'NG',
      dialCode: '+234',
      name: 'Nigeria',
      flagEmoji: '🇳🇬',
      currencyCode: 'NGN',
      currencyName: 'Nigerian naira',
      momoUssdTemplate: '*223*1*{recipient}*{amount}#',
      aliases: <String>['Nigeria'],
      providerAliases: <String>['mtn_nigeria', 'airtel', 'glo'],
      mobileNationalNumberPattern: r'^0?[789]0[1-9]\d{7}$',
      mobilePossibleLengths: <int>[10, 11],
      mobileExampleNational: '08031234567',
      mobileExampleE164: '+2348031234567',
      momoNumberLocalPattern: r'^0?[789]0[1-9]\d{7}$',
      momoNumberE164Pattern: r'^\+234[789]0[1-9]\d{7}$',
      phoneValidationSource: 'ITU E.164 / NCC Nigeria',
    ),
    CoolCountry(
      isoCode: 'RW',
      dialCode: '+250',
      name: 'Rwanda',
      flagEmoji: '🇷🇼',
      currencyCode: 'RWF',
      currencyName: 'Rwandan franc',
      momoUssdTemplate: '*182*1*1*{recipient}*{amount}#',
      momoCodeUssdTemplate: '*182*8*1*{recipient}*{amount}#',
      aliases: <String>['Rwanda'],
      providerAliases: <String>['mtn_rwanda', 'mtn', 'mtn rwanda'],
      mobileNationalNumberPattern: r'^0?7[23589]\d{7}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0781234567',
      mobileExampleE164: '+250781234567',
      momoNumberLocalPattern: r'^0?7[23589]\d{7}$',
      momoNumberE164Pattern: r'^\+2507[23589]\d{7}$',
      momoCodePattern: r'^\d{4,9}$',
      momoCodeMinLength: 4,
      momoCodeMaxLength: 9,
      momoCodeExample: '123456',
    ),
    CoolCountry(
      isoCode: 'ZA',
      dialCode: '+27',
      name: 'South Africa',
      flagEmoji: '🇿🇦',
      currencyCode: 'ZAR',
      currencyName: 'South African rand',
      momoUssdTemplate: '*120*668*1*{recipient}*{amount}#',
      aliases: <String>['South Africa'],
      mobileNationalNumberPattern: r'^0?[6-8]\d{8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0711234567',
      mobileExampleE164: '+27711234567',
      momoNumberLocalPattern: r'^0?[6-8]\d{8}$',
      momoNumberE164Pattern: r'^\+27[6-8]\d{8}$',
      phoneValidationSource: 'ITU E.164 / ICASA South Africa',
    ),
    CoolCountry(
      isoCode: 'SZ',
      dialCode: '+268',
      name: 'Eswatini',
      flagEmoji: '🇸🇿',
      currencyCode: 'SZL',
      currencyName: 'Swazi lilangeni',
      momoUssdTemplate: '*468*1*{recipient}*{amount}#',
      aliases: <String>['Eswatini', 'Swaziland', 'Eswatini (Swaziland)'],
      mobileNationalNumberPattern: r'^7[6-9]\d{6}$',
      mobilePossibleLengths: <int>[8],
      mobileExampleNational: '76123456',
      mobileExampleE164: '+26876123456',
      momoNumberLocalPattern: r'^7[6-9]\d{6}$',
      momoNumberE164Pattern: r'^\+2687[6-9]\d{6}$',
      phoneValidationSource: 'ITU E.164 / ESCCOM Eswatini',
    ),
    CoolCountry(
      isoCode: 'UG',
      dialCode: '+256',
      name: 'Uganda',
      flagEmoji: '🇺🇬',
      currencyCode: 'UGX',
      currencyName: 'Ugandan shilling',
      momoUssdTemplate: '*165*1*{recipient}*{amount}#',
      aliases: <String>['Uganda'],
      providerAliases: <String>['airtel', 'mtn_uganda', 'mtn'],
      mobileNationalNumberPattern: r'^0?[1-9]\d{7,8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0712345678',
      mobileExampleE164: '+256712345678',
      momoNumberLocalPattern: r'^0?[1-9]\d{7,8}$',
      momoNumberE164Pattern: r'^\+256[1-9]\d{7,8}$',
      phoneValidationSource: 'ITU E.164 / UCC Uganda',
    ),
    CoolCountry(
      isoCode: 'ZM',
      dialCode: '+260',
      name: 'Zambia',
      flagEmoji: '🇿🇲',
      currencyCode: 'ZMW',
      currencyName: 'Zambian kwacha',
      momoUssdTemplate: '*303*1*{recipient}*{amount}#',
      aliases: <String>['Zambia'],
      mobileNationalNumberPattern: r'^0?[79]\d{8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0955123456',
      mobileExampleE164: '+260955123456',
      momoNumberLocalPattern: r'^0?[79]\d{8}$',
      momoNumberE164Pattern: r'^\+260[79]\d{8}$',
      phoneValidationSource: 'ITU E.164 / ZICTA Zambia',
    ),
    CoolCountry(
      isoCode: 'ZW',
      dialCode: '+263',
      name: 'Zimbabwe',
      flagEmoji: '🇿🇼',
      currencyCode: 'ZWL',
      currencyName: 'Zimbabwean dollar',
      momoUssdTemplate: '*151*1*{recipient}*{amount}#',
      aliases: <String>['Zimbabwe'],
      mobileNationalNumberPattern: r'^0?7[1-8]\d{7}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0712345678',
      mobileExampleE164: '+263712345678',
      momoNumberLocalPattern: r'^0?7[1-8]\d{7}$',
      momoNumberE164Pattern: r'^\+2637[1-8]\d{7}$',
      phoneValidationSource: 'ITU E.164 / POTRAZ Zimbabwe',
    ),
    CoolCountry(
      isoCode: 'CD',
      dialCode: '+243',
      name: 'Democratic Republic of the Congo',
      flagEmoji: '🇨🇩',
      currencyCode: 'CDF',
      currencyName: 'Congolese franc',
      momoUssdTemplate: '*099*1*{recipient}*{amount}#',
      aliases: <String>[
        'DRC',
        'Congo Kinshasa',
        'Democratic Republic of Congo',
        'Democratic Republic of the Congo',
        'Democratic Republic of Congo (DRC)',
      ],
      providerAliases: <String>['orange', 'vodacom', 'airtel'],
      mobileNationalNumberPattern: r'^0?[89]\d{6,8}$',
      mobilePossibleLengths: <int>[7, 8, 9, 10],
      mobileExampleNational: '0991234567',
      mobileExampleE164: '+243991234567',
      momoNumberLocalPattern: r'^0?[89]\d{6,8}$',
      momoNumberE164Pattern: r'^\+243[89]\d{6,8}$',
      phoneValidationSource: 'ITU E.164 / ARPTC DRC',
    ),
    CoolCountry(
      isoCode: 'ET',
      dialCode: '+251',
      name: 'Ethiopia',
      flagEmoji: '🇪🇹',
      currencyCode: 'ETB',
      currencyName: 'Ethiopian birr',
      momoUssdTemplate: '*806*1*{recipient}*{amount}#',
      aliases: <String>['Ethiopia'],
      mobileNationalNumberPattern: r'^0?9\d{8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0911234567',
      mobileExampleE164: '+251911234567',
      momoNumberLocalPattern: r'^0?9\d{8}$',
      momoNumberE164Pattern: r'^\+2519\d{8}$',
      phoneValidationSource: 'ITU E.164 / ECA Ethiopia',
    ),
    CoolCountry(
      isoCode: 'GA',
      dialCode: '+241',
      name: 'Gabon',
      flagEmoji: '🇬🇦',
      currencyCode: 'XAF',
      currencyName: 'Central African CFA franc',
      momoUssdTemplate: '*222*1*{recipient}*{amount}#',
      aliases: <String>['Gabon'],
      mobileNationalNumberPattern: r'^0?[067]\d{6,7}$',
      mobilePossibleLengths: <int>[7, 8],
      mobileExampleNational: '06123456',
      mobileExampleE164: '+2416123456',
      momoNumberLocalPattern: r'^0?[067]\d{6,7}$',
      momoNumberE164Pattern: r'^\+241[067]\d{6,7}$',
      phoneValidationSource: 'ITU E.164 / ARCEP Gabon',
    ),
    CoolCountry(
      isoCode: 'MG',
      dialCode: '+261',
      name: 'Madagascar',
      flagEmoji: '🇲🇬',
      currencyCode: 'MGA',
      currencyName: 'Malagasy ariary',
      momoUssdTemplate: '*162*1*{recipient}*{amount}#',
      aliases: <String>['Madagascar'],
      mobileNationalNumberPattern: r'^0?3[2-49]\d{7}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0321234567',
      mobileExampleE164: '+261321234567',
      momoNumberLocalPattern: r'^0?3[2-49]\d{7}$',
      momoNumberE164Pattern: r'^\+2613[2-49]\d{7}$',
      phoneValidationSource: 'ITU E.164 / ARTEC Madagascar',
    ),
    CoolCountry(
      isoCode: 'SN',
      dialCode: '+221',
      name: 'Senegal',
      flagEmoji: '🇸🇳',
      currencyCode: 'XOF',
      currencyName: 'West African CFA franc',
      momoUssdTemplate: '*140*1*{recipient}*{amount}#',
      aliases: <String>['Senegal'],
      providerAliases: <String>['orange', 'free', 'expresso'],
      mobileNationalNumberPattern: r'^0?7[0-9]\d{7}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0701234567',
      mobileExampleE164: '+221701234567',
      momoNumberLocalPattern: r'^0?7[0-9]\d{7}$',
      momoNumberE164Pattern: r'^\+2217[0-9]\d{7}$',
      phoneValidationSource: 'ITU E.164 / ARTP Senegal',
    ),
    CoolCountry(
      isoCode: 'SL',
      dialCode: '+232',
      name: 'Sierra Leone',
      flagEmoji: '🇸🇱',
      currencyCode: 'SLL',
      currencyName: 'Sierra Leonean leone',
      momoUssdTemplate: '*277*1*{recipient}*{amount}#',
      aliases: <String>['Sierra Leone'],
      mobileNationalNumberPattern: r'^[2-9]\d{7}$',
      mobilePossibleLengths: <int>[8],
      mobileExampleNational: '25123456',
      mobileExampleE164: '+23225123456',
      momoNumberLocalPattern: r'^[2-9]\d{7}$',
      momoNumberE164Pattern: r'^\+232[2-9]\d{7}$',
      phoneValidationSource: 'ITU E.164 / NATCOM Sierra Leone',
    ),
    CoolCountry(
      isoCode: 'TZ',
      dialCode: '+255',
      name: 'Tanzania',
      flagEmoji: '🇹🇿',
      currencyCode: 'TZS',
      currencyName: 'Tanzanian shilling',
      momoUssdTemplate: '*150*00*1*{recipient}*{amount}#',
      aliases: <String>['Tanzania'],
      providerAliases: <String>['vodacom', 'tigo', 'airtel', 'mpesa'],
      mobileNationalNumberPattern: r'^0?[67]\d{8}$',
      mobilePossibleLengths: <int>[9, 10],
      mobileExampleNational: '0621234567',
      mobileExampleE164: '+255621234567',
      momoNumberLocalPattern: r'^0?[67]\d{8}$',
      momoNumberE164Pattern: r'^\+255[67]\d{8}$',
      phoneValidationSource: 'ITU E.164 / TCRA Tanzania',
    ),
  ];

  static CoolCountry get defaultCountry => byIsoCode('RW')!;

  static CoolCountry? byIsoCode(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    final normalized = _normalizeLookup(value);
    if (normalized.isEmpty) {
      return null;
    }

    for (final country in source) {
      if (country.isoCode.toLowerCase() == normalized) {
        return country;
      }
      for (final alias in country.aliases) {
        if (_normalizeLookup(alias) == normalized) {
          return country;
        }
      }
    }
    return null;
  }

  static CoolCountry? byDialCode(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
    for (final country in source) {
      if (country.dialCode == digits) {
        return country;
      }
    }
    return null;
  }

  static CoolCountry? byProviderId(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    final normalized = _normalizeLookup(value);
    if (normalized.isEmpty) {
      return null;
    }

    for (final country in source) {
      if (_normalizeLookup(country.providerId) == normalized) {
        return country;
      }
      for (final alias in country.providerAliases) {
        if (_normalizeLookup(alias) == normalized) {
          return country;
        }
      }
    }

    return null;
  }

  static CoolCountry? fromPhoneNumber(
    String? value, {
    Iterable<CoolCountry> source = all,
  }) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final phone = value.startsWith('+')
        ? value
        : '+${value.replaceAll(RegExp(r'[^0-9]'), '')}';
    final ordered = <CoolCountry>[...source]
      ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));

    for (final country in ordered) {
      if (phone.startsWith(country.dialCode)) {
        return country;
      }
    }

    return null;
  }

  static CoolCountry resolve({
    String? country,
    String? phone,
    String? providerId,
    Iterable<CoolCountry> source = all,
  }) {
    return byIsoCode(country, source: source) ??
        byDialCode(country, source: source) ??
        byProviderId(providerId, source: source) ??
        fromPhoneNumber(phone, source: source) ??
        defaultCountry;
  }

  static String normalizeCountryCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return defaultCountry.isoCode;
    }

    return byIsoCode(value)?.isoCode ??
        byDialCode(value)?.isoCode ??
        fromPhoneNumber(value)?.isoCode ??
        value.trim().toUpperCase();
  }

  static String normalizeProviderId({
    String? providerId,
    String? country,
    String? phone,
  }) {
    final resolvedCountry =
        byIsoCode(country) ??
        byDialCode(country) ??
        fromPhoneNumber(phone) ??
        byProviderId(providerId);

    if (resolvedCountry != null) {
      return resolvedCountry.providerId;
    }

    if (providerId != null && providerId.trim().isNotEmpty) {
      return providerId.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    }

    final normalizedCountry = country?.trim().toLowerCase();
    if (normalizedCountry != null && normalizedCountry.isNotEmpty) {
      return 'momo_$normalizedCountry';
    }

    return '';
  }

  static String _normalizeLookup(String? value) {
    return value
            ?.toLowerCase()
            .replaceAll('&', 'and')
            .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
            .trim() ??
        '';
  }
}
