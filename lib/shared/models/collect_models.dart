import 'package:flutter/foundation.dart';

import 'collect_profile_country_rules.dart';
export 'collect_profile_country_rules.dart';

part 'collect_model_json_helpers.dart';

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
const collectDefaultPrivacyPolicySections = [
  CollectPolicySection(
    title: 'Data we collect',
    body:
        'Collect stores your Collect ID, display name, selected country and local currency, WhatsApp sign-in phone, Rwanda MoMo provider and number, diaspora Revolut details, group memberships, contribution requests, ledger records, and permission status. On Android in Rwanda, MoMo receipt SMS is processed only with consent.',
  ),
  CollectPolicySection(
    title: 'How we use data',
    body:
        'We use this data to create and join groups, verify MoMo or diaspora bank contributions, keep ledgers accurate, show notifications, prevent misuse, provide support, and maintain reconciliation audit records.',
  ),
  CollectPolicySection(
    title: 'What stays private',
    body:
        'Sign-in phones, MoMo numbers, diaspora account details, payer details, raw receipt text, and support evidence are not shown on public group cards or public share links. Member-facing screens use Collect IDs and safe contribution status.',
  ),
  CollectPolicySection(
    title: 'Sharing',
    body:
        'We share only what is needed with service providers that operate authentication, hosting, storage, messaging, support, analytics, or contribution verification. We do not sell personal data.',
  ),
  CollectPolicySection(
    title: 'Choices and retention',
    body:
        'You can request account deletion, leave groups where supported, and contact support for correction requests. Ledger and reconciliation records may be retained where needed for audit, security, dispute, and legal reasons.',
  ),
];

const collectDefaultTermsSections = [
  CollectPolicySection(
    title: 'Using Collect',
    body:
        'Collect helps groups organize contributions, open Rwanda MoMo USSD, prepare diaspora bank-transfer requests, share group QR codes, and maintain a verified contribution ledger. You must use accurate group, receiver, beneficiary, and transfer information.',
  ),
  CollectPolicySection(
    title: 'Contribution rails',
    body:
        'Rwanda members approve MoMo payments in USSD; diaspora members approve bank transfers outside Collect in Revolut or their banking app. Collect never asks for a MoMo PIN, bank credentials, card details, OTP, or banking-app sign-in secrets.',
  ),
  CollectPolicySection(
    title: 'Group ownership',
    body:
        'Every member-created group is private and can be created only in the Android app. Group owners manage profile details and membership. Public groups are platform-sponsored and approved by Collect.',
  ),
  CollectPolicySection(
    title: 'Disputes and corrections',
    body:
        'If a contribution is missing, duplicated, returned, incorrect, or needs review, contact support. Collect may use request status, MoMo receipt facts, diaspora bank references, statements, and audit logs to investigate.',
  ),
  CollectPolicySection(
    title: 'Acceptable use',
    body:
        'Do not create misleading groups, impersonate another person, abuse QR links, submit false contribution claims, or use Collect to request illegal or unauthorized transfers.',
  ),
];

const collectDefaultAccountDeletionReasons = [
  AccountRequestReasonOption(
    key: 'no_longer_use_collect',
    label: 'I no longer use Collect',
  ),
  AccountRequestReasonOption(
    key: 'joined_by_mistake',
    label: 'I joined by mistake',
  ),
  AccountRequestReasonOption(
    key: 'prefer_not_to_keep_data',
    label: 'I prefer not to keep my data',
  ),
];

const collectDefaultCollectionTypeCatalog = CollectionTypeCatalogConfig(
  countryCode: 'RW',
  locale: 'en',
  types: [
    CollectionTypeCatalogItem(
      type: CollectionType.ikimina,
      label: 'Ikimina',
      shortPurpose: 'Group savings',
      iconKey: 'savings',
      defaultCategorySubtype: 'group_savings',
      defaultPurposeTemplateKey: 'group_savings',
      subtypes: [
        CollectionCatalogOption(key: 'group_savings', label: 'Group savings'),
        CollectionCatalogOption(
          key: 'family_friends',
          label: 'Family or friends',
        ),
        CollectionCatalogOption(
          key: 'community_event',
          label: 'Community event',
        ),
      ],
      purposeTemplates: [
        CollectionCatalogOption(key: 'group_savings', label: 'Group savings'),
        CollectionCatalogOption(key: 'member_support', label: 'Member support'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.sport,
      label: 'Sport',
      shortPurpose: 'Fan club support',
      iconKey: 'sport',
      defaultCategorySubtype: 'fan_club',
      defaultPurposeTemplateKey: 'fan_club_support',
      subtypes: [
        CollectionCatalogOption(key: 'fan_club', label: 'Fan club'),
        CollectionCatalogOption(key: 'team_support', label: 'Team support'),
        CollectionCatalogOption(key: 'away_travel', label: 'Away travel'),
      ],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'fan_club_support',
          label: 'Fan club support',
        ),
        CollectionCatalogOption(key: 'away_travel', label: 'Away travel'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.church,
      label: 'Church',
      shortPurpose: 'Offering and donations',
      iconKey: 'church',
      defaultCategorySubtype: 'offering',
      defaultPurposeTemplateKey: 'offering_and_donations',
      subtypes: [
        CollectionCatalogOption(key: 'offering', label: 'Offering'),
        CollectionCatalogOption(key: 'tithe', label: 'Tithe'),
        CollectionCatalogOption(
          key: 'project_support',
          label: 'Project support',
        ),
      ],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'offering_and_donations',
          label: 'Offering and donations',
        ),
        CollectionCatalogOption(key: 'church_project', label: 'Church project'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.wedding,
      label: 'Wedding',
      shortPurpose: 'Wedding contributions',
      iconKey: 'wedding',
      defaultCategorySubtype: 'committee',
      defaultPurposeTemplateKey: 'wedding_contributions',
      subtypes: [
        CollectionCatalogOption(key: 'committee', label: 'Committee'),
        CollectionCatalogOption(key: 'gift', label: 'Gift'),
        CollectionCatalogOption(
          key: 'ceremony_support',
          label: 'Ceremony support',
        ),
      ],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'wedding_contributions',
          label: 'Wedding contributions',
        ),
        CollectionCatalogOption(key: 'wedding_gifts', label: 'Wedding gifts'),
      ],
    ),
    CollectionTypeCatalogItem(
      type: CollectionType.other,
      label: 'Other',
      shortPurpose: 'Custom collection',
      iconKey: 'collections',
      defaultCategorySubtype: 'custom',
      defaultPurposeTemplateKey: 'custom_collection',
      subtypes: [CollectionCatalogOption(key: 'custom', label: 'Custom')],
      purposeTemplates: [
        CollectionCatalogOption(
          key: 'custom_collection',
          label: 'Custom collection',
        ),
      ],
    ),
  ],
);

enum CollectionType {
  ikimina,
  sport,
  church,
  wedding,
  other;

  static CollectionType fromJson(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'ikimina' ||
      'ibimina' ||
      'group_savings' ||
      'group savings' => CollectionType.ikimina,
      'sport' ||
      'sports' ||
      'fan_club' ||
      'fan club' ||
      'sports team' => CollectionType.sport,
      'church' || 'offering' || 'tithe' => CollectionType.church,
      'wedding' || 'wedding_contribution' => CollectionType.wedding,
      _ => CollectionType.other,
    };
  }

  String get storageValue => switch (this) {
    CollectionType.ikimina => 'ikimina',
    CollectionType.sport => 'sport',
    CollectionType.church => 'church',
    CollectionType.wedding => 'wedding',
    CollectionType.other => 'other',
  };

  String get label => switch (this) {
    CollectionType.ikimina => 'Ikimina',
    CollectionType.sport => 'Sport',
    CollectionType.church => 'Church',
    CollectionType.wedding => 'Wedding',
    CollectionType.other => 'Other',
  };

  String get shortPurpose => switch (this) {
    CollectionType.ikimina => 'Group savings',
    CollectionType.sport => 'Fan club support',
    CollectionType.church => 'Offering and donations',
    CollectionType.wedding => 'Wedding contributions',
    CollectionType.other => 'Custom collection',
  };
}

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
    final brand = _mapValue(json['brand']);
    final supportChannels = _mapList(json['support_channels']);
    final whatsApp = _firstByKey(supportChannels, 'support.whatsapp');
    final email = _firstByKey(supportChannels, 'support.email');
    const defaults = CollectRuntimeConfig.defaults;

    return CollectRuntimeConfig(
      brandDisplayName: _nonEmpty(
        brand['display_name'],
        defaults.brandDisplayName,
      ),
      legalName: _nonEmpty(brand['legal_name'], defaults.legalName),
      publicUrl: _nonEmpty(brand['public_url'], defaults.publicUrl),
      adminUrl: _nonEmpty(brand['admin_url'], defaults.adminUrl),
      appDownloadUrl: _nonEmpty(
        brand['app_download_url'],
        defaults.appDownloadUrl,
      ),
      regulatoryFooterNote: _nonEmpty(
        brand['regulatory_footer_note'],
        defaults.regulatoryFooterNote,
      ),
      whatsAppSupportPhone: _nonEmpty(
        whatsApp['value'],
        defaults.whatsAppSupportPhone,
      ),
      whatsAppSupportDisplay: _nonEmpty(
        whatsApp['display_value'],
        defaults.whatsAppSupportDisplay,
      ),
      supportEmail: _nonEmpty(email['value'], defaults.supportEmail),
    );
  }
}

@immutable
class CollectionTypeCatalogConfig {
  const CollectionTypeCatalogConfig({
    required this.countryCode,
    required this.locale,
    required this.types,
  });

  final String countryCode;
  final String locale;
  final List<CollectionTypeCatalogItem> types;

  static const defaults = collectDefaultCollectionTypeCatalog;

  factory CollectionTypeCatalogConfig.fromJson(Map<String, dynamic> json) {
    const fallback = CollectionTypeCatalogConfig.defaults;
    final types = [
      for (final item in _mapList(json['types']))
        CollectionTypeCatalogItem.fromJson(item),
    ];
    return CollectionTypeCatalogConfig(
      countryCode: _nonEmpty(json['country_code'], fallback.countryCode),
      locale: _nonEmpty(json['locale'], fallback.locale),
      types: types.isEmpty ? fallback.types : types,
    );
  }

  CollectionTypeCatalogItem optionFor(CollectionType type) {
    return types.firstWhere(
      (item) => item.type == type,
      orElse: () => CollectionTypeCatalogConfig.defaults.types.firstWhere(
        (item) => item.type == type,
      ),
    );
  }
}

@immutable
class CollectionTypeCatalogItem {
  const CollectionTypeCatalogItem({
    required this.type,
    required this.label,
    required this.shortPurpose,
    required this.iconKey,
    required this.defaultCategorySubtype,
    required this.defaultPurposeTemplateKey,
    required this.subtypes,
    required this.purposeTemplates,
  });

  final CollectionType type;
  final String label;
  final String shortPurpose;
  final String iconKey;
  final String defaultCategorySubtype;
  final String defaultPurposeTemplateKey;
  final List<CollectionCatalogOption> subtypes;
  final List<CollectionCatalogOption> purposeTemplates;

  factory CollectionTypeCatalogItem.fromJson(Map<String, dynamic> json) {
    final type = CollectionType.fromJson(json['key']);
    final fallback = CollectionTypeCatalogConfig.defaults.optionFor(type);
    final subtypes = [
      for (final item in _mapList(json['subtypes']))
        CollectionCatalogOption.fromJson(item),
    ];
    final purposeTemplates = [
      for (final item in _mapList(json['purpose_templates']))
        CollectionCatalogOption.fromJson(item),
    ];
    return CollectionTypeCatalogItem(
      type: type,
      label: _nonEmpty(json['label'], fallback.label),
      shortPurpose: _nonEmpty(json['short_purpose'], fallback.shortPurpose),
      iconKey: _nonEmpty(json['icon_key'], fallback.iconKey),
      defaultCategorySubtype: _nonEmpty(
        json['default_category_subtype'],
        fallback.defaultCategorySubtype,
      ),
      defaultPurposeTemplateKey: _nonEmpty(
        json['default_purpose_template_key'],
        fallback.defaultPurposeTemplateKey,
      ),
      subtypes: subtypes.isEmpty ? fallback.subtypes : subtypes,
      purposeTemplates: purposeTemplates.isEmpty
          ? fallback.purposeTemplates
          : purposeTemplates,
    );
  }

  String get defaultPurposeLabel {
    return purposeTemplates
        .firstWhere(
          (item) => item.key == defaultPurposeTemplateKey,
          orElse: () => CollectionCatalogOption(
            key: defaultPurposeTemplateKey,
            label: shortPurpose,
          ),
        )
        .label;
  }
}

@immutable
class CollectionCatalogOption {
  const CollectionCatalogOption({required this.key, required this.label});

  final String key;
  final String label;

  factory CollectionCatalogOption.fromJson(Map<String, dynamic> json) {
    return CollectionCatalogOption(
      key: _nonEmpty(json['key'], ''),
      label: _nonEmpty(json['label'], 'Option'),
    );
  }
}

@immutable
class CollectPolicyDocument {
  const CollectPolicyDocument({
    required this.kind,
    required this.title,
    required this.version,
    required this.locale,
    required this.sections,
  });

  final String kind;
  final String title;
  final String version;
  final String locale;
  final List<CollectPolicySection> sections;

  factory CollectPolicyDocument.defaults(String kind) {
    final normalized = kind.trim().toLowerCase();
    final isPrivacy = normalized == 'privacy';
    return CollectPolicyDocument(
      kind: isPrivacy ? 'privacy' : 'terms',
      title: isPrivacy ? 'Privacy Policy' : 'Terms & Conditions',
      version: 'local-fallback',
      locale: 'en',
      sections: isPrivacy
          ? collectDefaultPrivacyPolicySections
          : collectDefaultTermsSections,
    );
  }

  factory CollectPolicyDocument.fromJson(
    Map<String, dynamic> json, {
    required String fallbackKind,
  }) {
    final fallback = CollectPolicyDocument.defaults(fallbackKind);
    final sections = [
      for (final item in _mapList(json['sections']))
        CollectPolicySection.fromJson(item),
    ];
    return CollectPolicyDocument(
      kind: _nonEmpty(json['kind'], fallback.kind),
      title: _nonEmpty(json['title'], fallback.title),
      version: _nonEmpty(json['version'], fallback.version),
      locale: _nonEmpty(json['locale'], fallback.locale),
      sections: sections.isEmpty ? fallback.sections : sections,
    );
  }
}

@immutable
class CollectPolicySection {
  const CollectPolicySection({required this.title, required this.body});

  final String title;
  final String body;

  factory CollectPolicySection.fromJson(Map<String, dynamic> json) {
    return CollectPolicySection(
      title: _nonEmpty(json['title'], 'Policy'),
      body: _nonEmpty(json['body'], ''),
    );
  }
}

@immutable
class AccountRequestReasonOption {
  const AccountRequestReasonOption({required this.key, required this.label});

  final String key;
  final String label;

  factory AccountRequestReasonOption.fromJson(Map<String, dynamic> json) {
    return AccountRequestReasonOption(
      key: _nonEmpty(json['key'], ''),
      label: _nonEmpty(json['label'], 'Other'),
    );
  }
}

String _defaultRwandaMomoNumber(String whatsappPhone, String countryCode) {
  if (countryCode.trim().toUpperCase() != 'RW') return '';
  final digits = whatsappPhone.replaceAll(RegExp(r'\D'), '');
  if (RegExp(r'^2507[2389][0-9]{7}$').hasMatch(digits)) {
    return '0${digits.substring(3)}';
  }
  if (RegExp(r'^07[2389][0-9]{7}$').hasMatch(digits)) return digits;
  return '';
}

@immutable
class CollectProfile {
  const CollectProfile({
    required this.id,
    required this.publicId,
    required this.whatsappPhone,
    this.displayName = '',
    this.countryCode = '',
    this.currencyCode = '',
    this.momoProvider = '',
    this.momoNumber = '',
    this.revolutName = '',
    this.revolutLink = '',
    this.revolutAccount = '',
  });

  final String id;
  final String publicId;
  final String whatsappPhone;
  final String displayName;
  final String countryCode;
  final String currencyCode;
  final String momoProvider;
  final String momoNumber;
  final String revolutName;
  final String revolutLink;
  final String revolutAccount;

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
      id: json['id'] as String,
      publicId: json['public_id'] as String,
      whatsappPhone: whatsappPhone,
      displayName: (json['display_name'] as String?)?.trim() ?? '',
      countryCode: countryCode,
      currencyCode: storedCurrency?.length == 3
          ? storedCurrency!
          : CollectProfileCountryRules.currencyForCountry(countryCode),
      momoProvider: (json['momo_provider'] as String?)?.trim() ?? '',
      momoNumber:
          (json['momo_number'] as String?)?.trim() ??
          _defaultRwandaMomoNumber(whatsappPhone, countryCode),
      revolutName: (json['revolut_name'] as String?)?.trim() ?? '',
      revolutLink: (json['revolut_link'] as String?)?.trim() ?? '',
      revolutAccount: (json['revolut_account'] as String?)?.trim() ?? '',
    );
  }

  bool get isRwanda => countryCode.trim().toUpperCase() == 'RW';
  bool get isDiaspora => !isRwanda;
  bool get isEuropean =>
      CollectProfileCountryRules.isEuropeanCountry(countryCode);

  bool get isComplete =>
      displayName.trim().length >= 2 &&
      whatsappPhone.trim().isNotEmpty &&
      CollectProfileCountryRules.isSupportedCountry(countryCode) &&
      currencyCode.trim().toUpperCase() ==
          CollectProfileCountryRules.currencyForCountry(countryCode) &&
      (isRwanda
          ? const {'mtn_momo', 'airtel_money'}.contains(momoProvider) &&
                (momoProvider == 'mtn_momo'
                    ? RegExp(r'^07[89][0-9]{7}$').hasMatch(momoNumber)
                    : RegExp(r'^07[23][0-9]{7}$').hasMatch(momoNumber))
          : revolutName.trim().length >= 2 &&
                Uri.tryParse(revolutLink)?.host.endsWith('revolut.me') ==
                    true &&
                revolutAccount.trim().length >= 4);

  CollectProfile copyWith({
    String? displayName,
    String? countryCode,
    String? currencyCode,
    String? momoProvider,
    String? momoNumber,
    String? revolutName,
    String? revolutLink,
    String? revolutAccount,
  }) {
    return CollectProfile(
      id: id,
      publicId: publicId,
      whatsappPhone: whatsappPhone,
      displayName: displayName ?? this.displayName,
      countryCode: countryCode ?? this.countryCode,
      currencyCode: currencyCode ?? this.currencyCode,
      momoProvider: momoProvider ?? this.momoProvider,
      momoNumber: momoNumber ?? this.momoNumber,
      revolutName: revolutName ?? this.revolutName,
      revolutLink: revolutLink ?? this.revolutLink,
      revolutAccount: revolutAccount ?? this.revolutAccount,
    );
  }

  String get safeAlias => 'Collect ID $publicId';
}

@immutable
class CollectCollection {
  const CollectCollection({
    required this.id,
    required this.slug,
    required this.creatorUserId,
    required this.title,
    required this.description,
    this.collectionType = CollectionType.ikimina,
    this.categorySubtype,
    this.purposeLabel,
    this.receiverMomoNumber,
    this.receiverDisplayLabel = 'Primary MoMo receiver',
    this.receiverNetwork = 'mtn_momo',
    this.imageUrl,
    this.accentColorHex,
    this.isPublic = false,
    this.isPlatformSponsored = false,
    this.isCurrentUserMember = false,
    this.isRecurring = true,
    this.recurringCadence = 'monthly',
    String? visibilityStatus,
    this.suggestedAmountRwf,
    this.diasporaEnabled = false,
    this.diasporaRegions = const [],
    this.moderationStatus = 'not_requested',
    required this.createdAt,
  }) : visibilityStatus =
           visibilityStatus ?? (isPublic ? 'public_approved' : 'private');

  final String id;
  final String slug;
  final String creatorUserId;
  final String title;
  final String description;
  final CollectionType collectionType;
  final String? categorySubtype;
  final String? purposeLabel;
  final String? receiverMomoNumber;
  final String receiverDisplayLabel;
  final String receiverNetwork;
  final String? imageUrl;
  final String? accentColorHex;
  final bool isPublic;
  final bool isPlatformSponsored;
  final bool isCurrentUserMember;
  final bool isRecurring;
  final String recurringCadence;
  final String visibilityStatus;
  final int? suggestedAmountRwf;
  final bool diasporaEnabled;
  final List<String> diasporaRegions;
  final String moderationStatus;
  final DateTime createdAt;

  bool get isArchived => moderationStatus.trim().toLowerCase() == 'archived';

  factory CollectCollection.fromJson(Map<String, dynamic> json) {
    final receivers = json['collection_receivers'];
    Map<String, dynamic>? receiver;
    if (receivers is List && receivers.isNotEmpty) {
      receiver = Map<String, dynamic>.from(receivers.first as Map);
    }
    final receiverDisplayLabel =
        (receiver?['label'] as String?) ??
        (json['receiver_display_label'] as String?) ??
        'Primary MoMo receiver';
    return CollectCollection(
      id: json['id'] as String,
      slug: json['slug'] as String,
      creatorUserId: (json['creator_user_id'] as String?) ?? '',
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      collectionType: CollectionType.fromJson(
        json['collection_type'] ?? json['category'],
      ),
      categorySubtype: json['category_subtype'] as String?,
      purposeLabel: json['purpose_label'] as String?,
      receiverMomoNumber:
          (receiver?['momo_number'] as String?) ??
          (json['receiver_momo_number'] as String?),
      receiverDisplayLabel: receiverDisplayLabel,
      receiverNetwork:
          (receiver?['network'] as String?) ??
          (json['receiver_network'] as String?) ??
          'mtn_momo',
      imageUrl:
          (json['image_url'] as String?) ??
          (json['cover_image_url'] as String?) ??
          (json['photo_url'] as String?),
      accentColorHex:
          (json['accent_color_hex'] as String?) ??
          (json['card_color_hex'] as String?) ??
          (json['color_hex'] as String?),
      isPublic: _collectionIsPublic(json),
      isPlatformSponsored: (json['is_platform_sponsored'] as bool?) ?? false,
      isCurrentUserMember: (json['is_member'] as bool?) ?? false,
      isRecurring: (json['is_recurring'] as bool?) ?? true,
      recurringCadence:
          (json['recurring_cadence'] as String?) ??
          (json['contribution_frequency'] as String?) ??
          (json['frequency'] as String?) ??
          'monthly',
      visibilityStatus:
          (json['visibility_status'] as String?) ??
          ((json['is_public'] as bool?) == true
              ? 'public_approved'
              : 'private'),
      suggestedAmountRwf: (json['suggested_amount_rwf'] as num?)?.toInt(),
      diasporaEnabled: (json['diaspora_enabled'] as bool?) ?? false,
      diasporaRegions: _stringList(json['diaspora_regions']),
      moderationStatus:
          (json['moderation_status'] as String?) ?? 'not_requested',
      createdAt: _dateTime(json['created_at']),
    );
  }

  CollectCollection copyWith({
    String? creatorUserId,
    String? title,
    String? description,
    CollectionType? collectionType,
    String? categorySubtype,
    String? purposeLabel,
    String? receiverMomoNumber,
    String? receiverDisplayLabel,
    String? receiverNetwork,
    String? imageUrl,
    String? accentColorHex,
    bool? isPublic,
    bool? isPlatformSponsored,
    bool? isCurrentUserMember,
    bool? isRecurring,
    String? recurringCadence,
    String? visibilityStatus,
    int? suggestedAmountRwf,
    bool? diasporaEnabled,
    List<String>? diasporaRegions,
    String? moderationStatus,
  }) {
    return CollectCollection(
      id: id,
      slug: slug,
      creatorUserId: creatorUserId ?? this.creatorUserId,
      title: title ?? this.title,
      description: description ?? this.description,
      collectionType: collectionType ?? this.collectionType,
      categorySubtype: categorySubtype ?? this.categorySubtype,
      purposeLabel: purposeLabel ?? this.purposeLabel,
      receiverMomoNumber: receiverMomoNumber ?? this.receiverMomoNumber,
      receiverDisplayLabel: receiverDisplayLabel ?? this.receiverDisplayLabel,
      receiverNetwork: receiverNetwork ?? this.receiverNetwork,
      imageUrl: imageUrl ?? this.imageUrl,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      isPublic: isPublic ?? this.isPublic,
      isPlatformSponsored: isPlatformSponsored ?? this.isPlatformSponsored,
      isCurrentUserMember: isCurrentUserMember ?? this.isCurrentUserMember,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringCadence: recurringCadence ?? this.recurringCadence,
      visibilityStatus: visibilityStatus ?? this.visibilityStatus,
      suggestedAmountRwf: suggestedAmountRwf ?? this.suggestedAmountRwf,
      diasporaEnabled: diasporaEnabled ?? this.diasporaEnabled,
      diasporaRegions: diasporaRegions ?? this.diasporaRegions,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      createdAt: createdAt,
    );
  }
}

@immutable
class PaymentIntentDraft {
  const PaymentIntentDraft({
    required this.collectionId,
    required this.amountRwf,
  });

  final String collectionId;
  final int amountRwf;

  /// Compatibility name retained for APIs that expose a generic minor amount.
  /// Rwanda values are whole RWF; diaspora values are currency minor units.
  int get amountMinor => amountRwf;
}

@immutable
class BankTransferDestination {
  const BankTransferDestination({
    required this.id,
    required this.beneficiaryName,
    required this.iban,
    required this.ibanMasked,
    required this.bic,
    required this.bankName,
    this.currency = 'EUR',
    this.transferScheme = 'sepa_credit_transfer',
    this.supportsInstant = true,
    this.status = 'draft',
    this.isPlaceholder = false,
    this.enabled = false,
  });

  static const placeholder = BankTransferDestination(
    id: 'placeholder',
    beneficiaryName: 'PLACEHOLDER — DO NOT TRANSFER',
    iban: 'XX00PLACEHOLDER0000000000',
    ibanMasked: 'XX00••••0000',
    bic: 'PLACEHOL',
    bankName: 'PLACEHOLDER BANK',
    isPlaceholder: true,
  );

  final String id;
  final String beneficiaryName;
  final String iban;
  final String ibanMasked;
  final String bic;
  final String bankName;
  final String currency;
  final String transferScheme;
  final bool supportsInstant;
  final String status;
  final bool isPlaceholder;
  final bool enabled;

  factory BankTransferDestination.fromJson(Map<String, dynamic> json) {
    return BankTransferDestination(
      id: (json['id'] as String?) ?? 'unavailable',
      beneficiaryName:
          (json['beneficiary_name'] as String?) ?? 'Beneficiary unavailable',
      iban: (json['iban'] as String?) ?? '',
      ibanMasked: (json['iban_masked'] as String?) ?? '',
      bic: (json['bic'] as String?) ?? '',
      bankName: (json['bank_name'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'EUR',
      transferScheme:
          (json['transfer_scheme'] as String?) ?? 'sepa_credit_transfer',
      supportsInstant: json['supports_instant'] != false,
      status: (json['status'] as String?) ?? 'draft',
      isPlaceholder: json['is_placeholder'] == true,
      enabled: json['enabled'] == true,
    );
  }
}

@immutable
class PaymentIntentModel {
  const PaymentIntentModel({
    required this.id,
    required this.collectionId,
    int? expectedAmountMinor,
    int? expectedAmountRwf,
    this.rail = 'diaspora_bank',
    this.receiverMomoNumber = '',
    this.receiverMomoNumberHash = '',
    this.receiverMomoLabel = '',
    this.momoNetwork = 'mtn_momo',
    this.senderPhoneHash = '',
    this.transferReference = '',
    this.destination = BankTransferDestination.placeholder,
    this.currency = 'EUR',
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  }) : expectedAmountMinor = expectedAmountMinor ?? expectedAmountRwf ?? 0;

  final String id;
  final String collectionId;
  final int expectedAmountMinor;
  final String rail;
  final String receiverMomoNumber;
  final String receiverMomoNumberHash;
  final String receiverMomoLabel;
  final String momoNetwork;
  final String senderPhoneHash;
  final String transferReference;
  final BankTransferDestination destination;
  final String currency;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;

  int get expectedAmountRwf => expectedAmountMinor;
  bool get isRwandaMomo => rail == 'rwanda_momo';
  String get receiverLabel =>
      isRwandaMomo ? receiverMomoLabel : destination.beneficiaryName;
  String get network => isRwandaMomo ? momoNetwork : 'sepa';

  bool get isAwaitingTransfer =>
      (isRwandaMomo
              ? const {'pending'}
              : const {
                  'awaiting_transfer',
                  'handoff_opened',
                  'awaiting_bank_evidence',
                  'received_unreconciled',
                })
          .contains(status) &&
      DateTime.now().toUtc().isBefore(expiresAt.toUtc());

  factory PaymentIntentModel.fromJson(Map<String, dynamic> json) {
    final createdAt = _dateTime(json['created_at']);
    final expiresAt = _dateTime(json['expires_at']);
    final storedStatus = (json['status'] as String?) ?? 'awaiting_transfer';
    final destinationJson = json['destination'] ?? json['destination_snapshot'];
    return PaymentIntentModel(
      id: json['id'] as String,
      collectionId: json['collection_id'] as String,
      expectedAmountMinor:
          (json['amount_minor'] as num?)?.toInt() ??
          (json['expected_amount_rwf'] as num?)?.toInt() ??
          0,
      rail:
          json['rail']?.toString() ??
          (json['receiver_momo_number'] != null
              ? 'rwanda_momo'
              : 'diaspora_bank'),
      receiverMomoNumber:
          (json['receiver_momo_number'] as String?)?.trim() ?? '',
      receiverMomoNumberHash:
          (json['receiver_momo_number_hash'] as String?)?.trim() ?? '',
      receiverMomoLabel: (json['receiver_label'] as String?)?.trim() ?? '',
      momoNetwork: (json['network'] as String?)?.trim() ?? 'mtn_momo',
      senderPhoneHash: (json['sender_phone_hash'] as String?)?.trim() ?? '',
      transferReference: (json['transfer_reference'] as String?) ?? '',
      destination: destinationJson is Map
          ? BankTransferDestination.fromJson(
              Map<String, dynamic>.from(destinationJson),
            )
          : BankTransferDestination.placeholder,
      currency: (json['currency'] as String?) ?? 'EUR',
      status:
          const {
                'awaiting_transfer',
                'handoff_opened',
                'awaiting_bank_evidence',
              }.contains(storedStatus) &&
              !expiresAt.isAfter(DateTime.now().toUtc())
          ? 'expired'
          : storedStatus,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

@immutable
class Contribution {
  const Contribution({
    required this.id,
    required this.collectionId,
    required this.amountRwf,
    this.currency = 'EUR',
    required this.supporterLabel,
    required this.createdAt,
    this.transactionId,
    this.isCurrentUserContribution = false,
  });

  final String id;
  final String collectionId;
  final int amountRwf;
  final String currency;
  final String supporterLabel;
  final DateTime createdAt;
  final String? transactionId;
  final bool isCurrentUserContribution;

  int get amountMinor => amountRwf;

  factory Contribution.fromJson(Map<String, dynamic> json) {
    return Contribution(
      id: (json['payment_id'] as String?) ?? json['id'] as String,
      collectionId: json['collection_id'] as String,
      amountRwf:
          (json['amount_minor'] as num?)?.toInt() ??
          (json['amount_rwf'] as num?)?.toInt() ??
          0,
      currency: (json['currency'] as String?) ?? 'EUR',
      supporterLabel:
          (json['supporter_label'] as String?) ??
          (json['contributor_public_id'] == null
              ? 'Collect member'
              : 'Collect ID ${json['contributor_public_id']}'),
      createdAt: _dateTime(json['posted_at'] ?? json['created_at']),
      transactionId: json['transaction_id'] as String?,
      isCurrentUserContribution: json['is_current_user_contribution'] == true,
    );
  }
}

@immutable
class ParsedPaymentEvent {
  const ParsedPaymentEvent({
    required this.id,
    required this.amountRwf,
    required this.transactionId,
    required this.senderLabel,
    required this.allocationStatus,
    required this.confidence,
    required this.createdAt,
    this.collectionId,
  });

  final String id;
  final int amountRwf;
  final String? transactionId;
  final String senderLabel;
  final String allocationStatus;
  final double confidence;
  final DateTime createdAt;
  final String? collectionId;

  factory ParsedPaymentEvent.fromJson(Map<String, dynamic> json) {
    return ParsedPaymentEvent(
      id: json['id'] as String,
      amountRwf: (json['amount_rwf'] as num?)?.toInt() ?? 0,
      transactionId: json['transaction_id'] as String?,
      senderLabel: 'Bank SMS',
      allocationStatus: (json['allocation_status'] as String?) ?? 'unallocated',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      createdAt: _dateTime(json['created_at']),
      collectionId: json['collection_id'] as String?,
    );
  }
}

@immutable
class CollectionSummary {
  const CollectionSummary({
    required this.amountRaisedRwf,
    required this.supporterCount,
    this.currentUserBalanceRwf = 0,
    this.currency = 'EUR',
  });

  final int amountRaisedRwf;
  final int supporterCount;
  final int currentUserBalanceRwf;
  final String currency;

  int get amountRaisedMinor => amountRaisedRwf;
  int get currentUserBalanceMinor => currentUserBalanceRwf;

  factory CollectionSummary.fromJson(Map<String, dynamic> json) {
    return CollectionSummary(
      amountRaisedRwf:
          (json['amount_raised_minor'] as num?)?.toInt() ??
          (json['amount_raised_rwf'] as num?)?.toInt() ??
          0,
      supporterCount: (json['supporter_count'] as num?)?.toInt() ?? 0,
      currentUserBalanceRwf:
          (json['current_user_balance_minor'] as num?)?.toInt() ??
          (json['current_user_balance_rwf'] as num?)?.toInt() ??
          0,
      currency: (json['currency'] as String?) ?? 'EUR',
    );
  }
}

@immutable
class NotificationPreferences {
  const NotificationPreferences({
    this.contributionConfirmations = true,
    this.paymentReminders = true,
    this.groupUpdates = true,
    this.securityNotices = true,
  });

  final bool contributionConfirmations;
  final bool paymentReminders;
  final bool groupUpdates;
  final bool securityNotices;

  static const defaults = NotificationPreferences();

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      contributionConfirmations:
          (json['contribution_confirmations'] as bool?) ?? true,
      paymentReminders: (json['payment_reminders'] as bool?) ?? true,
      groupUpdates: (json['group_updates'] as bool?) ?? true,
      securityNotices: (json['security_notices'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contribution_confirmations': contributionConfirmations,
      'payment_reminders': paymentReminders,
      'group_updates': groupUpdates,
      'security_notices': securityNotices,
    };
  }

  NotificationPreferences copyWith({
    bool? contributionConfirmations,
    bool? paymentReminders,
    bool? groupUpdates,
    bool? securityNotices,
  }) {
    return NotificationPreferences(
      contributionConfirmations:
          contributionConfirmations ?? this.contributionConfirmations,
      paymentReminders: paymentReminders ?? this.paymentReminders,
      groupUpdates: groupUpdates ?? this.groupUpdates,
      securityNotices: securityNotices ?? this.securityNotices,
    );
  }
}

@immutable
class NotificationEvent {
  const NotificationEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
    this.collectionId,
    this.deepLink,
    this.sentAt,
    this.readAt,
  });

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String status;
  final DateTime createdAt;
  final String? collectionId;
  final String? deepLink;
  final DateTime? sentAt;
  final DateTime? readAt;

  factory NotificationEvent.fromJson(Map<String, dynamic> json) {
    return NotificationEvent(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      collectionId: json['collection_id'] as String?,
      type: (json['type'] as String?) ?? 'group_update',
      title: (json['title'] as String?) ?? 'Notification',
      body: (json['body'] as String?) ?? '',
      deepLink: json['deep_link'] as String?,
      status: (json['status'] as String?) ?? 'queued',
      createdAt: _dateTime(json['created_at']),
      sentAt: json['sent_at'] == null ? null : _dateTime(json['sent_at']),
      readAt: json['read_at'] == null ? null : _dateTime(json['read_at']),
    );
  }

  bool get unread => status != 'read';

  NotificationEvent copyWith({String? status, DateTime? readAt}) {
    return NotificationEvent(
      id: id,
      userId: userId,
      collectionId: collectionId,
      type: type,
      title: title,
      body: body,
      deepLink: deepLink,
      status: status ?? this.status,
      createdAt: createdAt,
      sentAt: sentAt,
      readAt: readAt ?? this.readAt,
    );
  }
}

@immutable
class CollectMember {
  const CollectMember({
    required this.publicId,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  final String publicId;
  final String role;
  final String status;
  final DateTime joinedAt;

  factory CollectMember.fromJson(Map<String, dynamic> json) {
    return CollectMember(
      publicId: (json['public_id'] as String?) ?? '000000',
      role: (json['role'] as String?) ?? 'member',
      status: (json['status'] as String?) ?? 'active',
      joinedAt: _dateTime(json['joined_at'] ?? json['created_at']),
    );
  }

  String get safeLabel => 'Collect ID $publicId';
}

@immutable
class OwnerGroupHealth {
  const OwnerGroupHealth({
    required this.collectionId,
    required this.smsAccessEnabled,
    required this.receiverConfigured,
    required this.pendingPaymentIntents,
    required this.needsReviewEvents,
    required this.lastSyncedAt,
  });

  final String collectionId;
  final bool smsAccessEnabled;
  final bool receiverConfigured;
  final int pendingPaymentIntents;
  final int needsReviewEvents;
  final DateTime? lastSyncedAt;

  factory OwnerGroupHealth.fromJson(Map<String, dynamic> json) {
    return OwnerGroupHealth(
      collectionId: json['collection_id'] as String,
      smsAccessEnabled: (json['sms_access_enabled'] as bool?) ?? false,
      receiverConfigured: (json['receiver_configured'] as bool?) ?? false,
      pendingPaymentIntents:
          (json['pending_payment_intents'] as num?)?.toInt() ?? 0,
      needsReviewEvents: (json['needs_review_events'] as num?)?.toInt() ?? 0,
      lastSyncedAt: json['last_synced_at'] == null
          ? null
          : _dateTime(json['last_synced_at']),
    );
  }

  bool get ready => smsAccessEnabled && receiverConfigured;
}
