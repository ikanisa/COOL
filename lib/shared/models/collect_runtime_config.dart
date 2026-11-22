import 'package:flutter/foundation.dart' show immutable;

import 'collect_model_json_helpers.dart';

const collectDefaultBrandDisplayName = 'Collect by IKANISA';
const collectDefaultLegalName = 'IKANISA Ltd.';
const collectDefaultPublicUrl = 'https://collect.ikanisa.com';
const collectDefaultAdminUrl = 'https://admin.collect.ikanisa.com';
const collectGooglePlayUrl =
    'https://play.google.com/store/apps/details?id=app.cool.mobile';
const collectAppleAppStoreId = '6783960331';
const collectAppleAppStoreUrl =
    'https://apps.apple.com/app/id$collectAppleAppStoreId';
const collectDefaultAppDownloadUrl = collectGooglePlayUrl;
const collectDefaultRegulatoryFooterNote =
    'IKANISA Ltd. operates Collect, a standalone group-contribution record system.';
const collectDefaultWhatsAppSupportPhone = '250795588248';
const collectDefaultWhatsAppSupportDisplay = '+250 795 588 248';
const collectDefaultSupportEmail = 'info@ikanisa.com';

@immutable
class CollectRuntimeConfig {
  const CollectRuntimeConfig({
    required this.brandDisplayName,
    required this.legalName,
    required this.publicUrl,
    required this.adminUrl,
    required this.appDownloadUrl,
    required this.regulatoryFooterNote,
    required this.whatsAppSupportPhone,
    required this.whatsAppSupportDisplay,
    required this.supportEmail,
  });

  static const defaults = CollectRuntimeConfig(
    brandDisplayName: collectDefaultBrandDisplayName,
    legalName: collectDefaultLegalName,
    publicUrl: collectDefaultPublicUrl,
    adminUrl: collectDefaultAdminUrl,
    appDownloadUrl: collectDefaultAppDownloadUrl,
    regulatoryFooterNote: collectDefaultRegulatoryFooterNote,
    whatsAppSupportPhone: collectDefaultWhatsAppSupportPhone,
    whatsAppSupportDisplay: collectDefaultWhatsAppSupportDisplay,
    supportEmail: collectDefaultSupportEmail,
  );

  final String brandDisplayName;
  final String legalName;
  final String publicUrl;
  final String adminUrl;
  final String appDownloadUrl;
  final String regulatoryFooterNote;
  final String whatsAppSupportPhone;
  final String whatsAppSupportDisplay;
  final String supportEmail;

  factory CollectRuntimeConfig.fromJson(Map<String, dynamic> json) {
    final brand = modelJsonMap(json['brand']);
    final supportChannels = modelJsonMaps(json['support_channels']);
    final whatsApp = _firstByKey(supportChannels, 'support.whatsapp');
    final email = _firstByKey(supportChannels, 'support.email');
    const defaults = CollectRuntimeConfig.defaults;

    return CollectRuntimeConfig(
      brandDisplayName: nonEmptyModelText(
        brand['display_name'],
        defaults.brandDisplayName,
      ),
      legalName: nonEmptyModelText(brand['legal_name'], defaults.legalName),
      publicUrl: nonEmptyModelText(brand['public_url'], defaults.publicUrl),
      adminUrl: nonEmptyModelText(brand['admin_url'], defaults.adminUrl),
      appDownloadUrl: nonEmptyModelText(
        brand['app_download_url'],
        defaults.appDownloadUrl,
      ),
      regulatoryFooterNote: nonEmptyModelText(
        brand['regulatory_footer_note'],
        defaults.regulatoryFooterNote,
      ),
      whatsAppSupportPhone: nonEmptyModelText(
        whatsApp['value'],
        defaults.whatsAppSupportPhone,
      ),
      whatsAppSupportDisplay: nonEmptyModelText(
        whatsApp['display_value'],
        defaults.whatsAppSupportDisplay,
      ),
      supportEmail: nonEmptyModelText(email['value'], defaults.supportEmail),
    );
  }
}

Map<String, dynamic> _firstByKey(List<Map<String, dynamic>> rows, String key) {
  return rows.firstWhere(
    (item) => item['key'] == key,
    orElse: () => const <String, dynamic>{},
  );
}
