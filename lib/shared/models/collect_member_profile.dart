import 'package:flutter/foundation.dart' show immutable;

import '../../core/data/exact_json_values.dart';

import 'collect_profile_country_rules.dart';

@immutable
class CollectProfile {
  const CollectProfile({
    required this.id,
    required this.publicId,
    required this.whatsappPhone,
    this.countryCode = '',
    this.currencyCode = '',
    this.momoProvider = '',
    this.momoNumber = '',
    this.momoPayCode = '',
  });

  final String id;
  final String publicId;
  final String whatsappPhone;
  final String countryCode;
  final String currencyCode;
  final String momoProvider;
  final String momoNumber;
  final String momoPayCode;

  factory CollectProfile.fromJson(Map<String, dynamic> json) {
    final whatsappPhone = (json['whatsapp_phone'] as String?)?.trim() ?? '';
    final countryCode = CollectProfileCountryRules.resolveCountryCode(
      storedCountryCode: json['country_code']?.toString(),
      whatsappPhone: whatsappPhone,
    );
    final storedCurrency = (json['currency_code'] as String?)
        ?.trim()
        .toUpperCase();
    return CollectProfile(
      id: exactJsonIdentifier(json['id'], field: 'profile.id'),
      publicId: exactJsonIdentifier(
        json['public_id'],
        field: 'profile.public_id',
      ),
      whatsappPhone: whatsappPhone,
      countryCode: countryCode,
      currencyCode: storedCurrency?.length == 3
          ? storedCurrency!
          : CollectProfileCountryRules.currencyForCountry(countryCode),
      momoProvider: (json['momo_provider'] as String?)?.trim() ?? '',
      // A sign-in phone is not evidence of a saved MoMo account. Missing
      // account data must leave the profile incomplete until it is supplied.
      momoNumber: (json['momo_number'] as String?)?.trim() ?? '',
      momoPayCode: (json['momo_pay_code'] as String?)?.trim() ?? '',
    );
  }

  bool get isRwanda => countryCode.trim().toUpperCase() == 'RW';
  bool get isComplete {
    // A compact international spelling represents the same saved Rwanda
    // number. Project it only for readiness; keep the stored value intact.
    final international = RegExp(
      r'^(?:\+250|250)(7[2389][0-9]{7})$',
    ).firstMatch(momoNumber);
    final readinessNumber =
        international == null || international.end != momoNumber.length
        ? momoNumber
        : '0${international.group(1)!}';
    return RegExp(r'^\d{6}$').hasMatch(publicId) &&
        whatsappPhone.trim().isNotEmpty &&
        isRwanda &&
        currencyCode == 'RWF' &&
        const {'mtn_momo', 'airtel_money'}.contains(momoProvider) &&
        (momoProvider == 'mtn_momo'
            ? RegExp(r'^07[89][0-9]{7}$').hasMatch(readinessNumber)
            : RegExp(r'^07[23][0-9]{7}$').hasMatch(readinessNumber));
  }

  CollectProfile copyWith({
    String? countryCode,
    String? currencyCode,
    String? momoProvider,
    String? momoNumber,
    String? momoPayCode,
  }) {
    return CollectProfile(
      id: id,
      publicId: publicId,
      whatsappPhone: whatsappPhone,
      countryCode: countryCode ?? this.countryCode,
      currencyCode: currencyCode ?? this.currencyCode,
      momoProvider: momoProvider ?? this.momoProvider,
      momoNumber: momoNumber ?? this.momoNumber,
      momoPayCode: momoPayCode ?? this.momoPayCode,
    );
  }

  String get safeAlias => 'Collect ID $publicId';
}
