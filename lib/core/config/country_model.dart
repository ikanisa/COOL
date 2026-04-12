part of 'country_catalog.dart';

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
    Object? read(String snakeCase, [String? camelCase]) =>
        json[snakeCase] ?? (camelCase == null ? null : json[camelCase]);

    return CoolCountry(
      isoCode: read('iso_code', 'isoCode')?.toString() ?? '',
      dialCode: read('dial_code', 'dialCode')?.toString() ?? '',
      name:
          read('country_name', 'countryName')?.toString() ??
          read('name')?.toString() ??
          read('display_name', 'displayName')?.toString() ??
          '',
      flagEmoji: read('flag_emoji', 'flagEmoji')?.toString() ?? '',
      currencyCode: read('currency_code', 'currencyCode')?.toString() ?? '',
      currencyName: read('currency_name', 'currencyName')?.toString() ?? '',
      providerIdValue:
          read('momo_provider_id', 'momoProviderId')?.toString() ??
          read('provider_id', 'providerId')?.toString(),
      momoUssdTemplate:
          read(
            'momo_number_ussd_template',
            'momoNumberUssdTemplate',
          )?.toString() ??
          read('momo_ussd_template', 'momoUssdTemplate')?.toString() ??
          '',
      momoCodeUssdTemplate:
          read(
                'momo_code_ussd_template',
                'momoCodeUssdTemplate',
              )?.toString().trim().isEmpty ??
              true
          ? null
          : read('momo_code_ussd_template', 'momoCodeUssdTemplate')?.toString(),
      aliases: _asStringList(read('country_aliases', 'aliases')),
      providerAliases: _asStringList(
        read('momo_provider_aliases', 'providerAliases'),
      ),
      mobileNationalNumberPattern: read(
        'mobile_national_number_pattern',
        'mobileNationalNumberPattern',
      )?.toString(),
      mobilePossibleLengths: _asIntList(
        read('mobile_possible_lengths', 'mobilePossibleLengths'),
      ),
      mobileExampleNational: read(
        'mobile_example_national',
        'mobileExampleNational',
      )?.toString(),
      mobileExampleE164: read(
        'mobile_example_e164',
        'mobileExampleE164',
      )?.toString(),
      momoNumberLocalPattern: read(
        'momo_number_local_pattern',
        'momoNumberLocalPattern',
      )?.toString(),
      momoNumberE164Pattern: read(
        'momo_number_e164_pattern',
        'momoNumberE164Pattern',
      )?.toString(),
      momoNumberUssdRegex: read(
        'momo_number_ussd_regex',
        'momoNumberUssdRegex',
      )?.toString(),
      momoNumberUssdExample: read(
        'momo_number_ussd_example',
        'momoNumberUssdExample',
      )?.toString(),
      momoCodeKind: read('momo_code_kind', 'momoCodeKind')?.toString(),
      momoCodePattern: read('momo_code_pattern', 'momoCodePattern')?.toString(),
      momoCodeMinLength: _asIntOrNull(
        read('momo_code_min_length', 'momoCodeMinLength'),
      ),
      momoCodeMaxLength: _asIntOrNull(
        read('momo_code_max_length', 'momoCodeMaxLength'),
      ),
      momoCodeExample: read('momo_code_example', 'momoCodeExample')?.toString(),
      momoCodeUssdRegex: read(
        'momo_code_ussd_regex',
        'momoCodeUssdRegex',
      )?.toString(),
      momoCodeUssdExample: read(
        'momo_code_ussd_example',
        'momoCodeUssdExample',
      )?.toString(),
      phoneValidationSource: read(
        'phone_validation_source',
        'phoneValidationSource',
      )?.toString(),
      momoUssdSource: read('momo_ussd_source', 'momoUssdSource')?.toString(),
      validationNotes: read('validation_notes', 'validationNotes')?.toString(),
    );
  }

  String buildUssdCode({
    required String recipientMomo,
    int? amount,
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

    var ussdCode = template.replaceAll('{recipient}', recipient);
    if (amount != null && amount > 0) {
      ussdCode = ussdCode.replaceAll('{amount}', amount.toString());
    } else {
      ussdCode = ussdCode
          .replaceAll('*{amount}', '')
          .replaceAll('{amount}', '');
    }

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
        : mobileExampleE164?.trim().isNotEmpty ?? false
        ? normalizeNationalPhone(mobileExampleE164!.trim())
        : '07XXXXXXX';
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
