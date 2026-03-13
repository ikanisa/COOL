import 'package:intl/intl.dart';

import '../../../core/config/country_catalog.dart';

enum PartnerPaymentRouteStatus {
  draft,
  active,
  inactive;

  static PartnerPaymentRouteStatus fromValue(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'active' => PartnerPaymentRouteStatus.active,
      'inactive' => PartnerPaymentRouteStatus.inactive,
      _ => PartnerPaymentRouteStatus.draft,
    };
  }
}

class PartnerPaymentRoute {
  const PartnerPaymentRoute({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    required this.partnerSlug,
    required this.countryCode,
    required this.providerId,
    required this.recipientCode,
    required this.reconciliationLabel,
    required this.status,
  });

  factory PartnerPaymentRoute.fromJson(Map<String, dynamic> json) {
    return PartnerPaymentRoute(
      id: json['id']?.toString() ?? '',
      partnerId: json['partner_id']?.toString() ?? '',
      partnerName: json['partner_name']?.toString() ?? 'Partner',
      partnerSlug: json['partner_slug']?.toString() ?? '',
      countryCode: CoolCountryCatalog.normalizeCountryCode(
        json['country']?.toString(),
      ),
      providerId: json['provider']?.toString().trim() ?? '',
      recipientCode: json['recipient_code']?.toString().trim() ?? '',
      reconciliationLabel:
          json['reconciliation_label']?.toString().trim() ?? '',
      status: PartnerPaymentRouteStatus.fromValue(json['status']?.toString()),
    );
  }

  final String id;
  final String partnerId;
  final String partnerName;
  final String partnerSlug;
  final String countryCode;
  final String providerId;
  final String recipientCode;
  final String reconciliationLabel;
  final PartnerPaymentRouteStatus status;

  bool get isActive => status == PartnerPaymentRouteStatus.active;

  CoolCountry get country =>
      CoolCountryCatalog.byIsoCode(countryCode) ??
      CoolCountryCatalog.defaultCountry;

  String get providerLabel =>
      _providerLabel(providerId: providerId, country: country);

  String get payToLabel => '$providerLabel code $recipientCode';

  String get ussdPattern {
    final template = country.momoCodeUssdTemplate;
    if (template == null || template.trim().isEmpty) {
      return '';
    }

    return template
        .replaceAll('{recipient}', recipientCode)
        .replaceAll('{amount}', '[amount]');
  }

  String ussdCode(int amount) {
    return country.buildUssdCode(
      recipientMomo: recipientCode,
      amount: amount,
      recipientType: MomoRecipientType.code,
    );
  }

  String amountLabel(int amount) {
    return formatPartnerPaymentAmount(
      amount,
      currencyCode: country.currencyCode,
    );
  }

  String feesLabel({int amount = 0}) {
    return formatPartnerPaymentAmount(
      amount,
      currencyCode: country.currencyCode,
    );
  }
}

String formatPartnerPaymentAmount(int amount, {String currencyCode = 'RWF'}) {
  return '${NumberFormat.decimalPattern('en').format(amount)} $currencyCode';
}

String _providerLabel({
  required String providerId,
  required CoolCountry country,
}) {
  return switch (providerId.trim().toLowerCase()) {
    'mtn_rwanda' => 'MTN MoMo',
    'mtn' => 'MTN MoMo',
    'airtel' => 'Airtel Money',
    'orange' => 'Orange Money',
    _ =>
      country.providerId == providerId.trim().toLowerCase()
          ? '${country.name} MoMo'
          : providerId.trim().isEmpty
          ? '${country.name} MoMo'
          : providerId.trim(),
  };
}
