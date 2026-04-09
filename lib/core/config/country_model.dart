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
