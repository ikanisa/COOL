import 'package:flutter/foundation.dart';

import '../../core/security/phone_normalizer.dart';

part 'collect_model_json_helpers.dart';

const _unsetProfileField = Object();
const collectDefaultBrandDisplayName = 'Collect by IKANISA';
const collectDefaultLegalName = 'IKANISA Ltd.';
const collectDefaultPublicUrl = 'https://collect.ikanisa.com';
const collectDefaultAdminUrl = 'https://admin.collect.ikanisa.com';
const collectDefaultAppDownloadUrl =
    'https://play.google.com/store/apps/details?id=app.cool.mobile';
const collectDefaultRegulatoryFooterNote =
    'IKANISA Ltd. is a registered technology company. Savings, credit and insurance products are provided by licensed partner institutions where approved arrangements apply.';
const collectDefaultWhatsAppSupportPhone = '250795588248';
const collectDefaultWhatsAppSupportDisplay = '+250 795 588 248';
const collectDefaultSupportEmail = 'info@ikanisa.com';
const collectDefaultUssdCode = '*182*8*1*41258*2000#';

const collectDefaultPrivacyPolicySections = [
  CollectPolicySection(
    title: 'Data we collect',
    body:
        'Collect stores your Collect ID, WhatsApp sign-in phone, optional MoMo account, group memberships, group profile details, payment requests, contribution records, and permission status. Group owners may allow Collect to process MoMo SMS evidence for payment matching.',
  ),
  CollectPolicySection(
    title: 'How we use data',
    body:
        'We use this data to create and join groups, verify contributions, keep ledgers accurate, show notifications, prevent misuse, provide support, and maintain audit records for payment disputes.',
  ),
  CollectPolicySection(
    title: 'What stays private',
    body:
        'Receiver MoMo numbers, private confirmation text, sign-in phones, and support evidence are not shown on public group cards or public share links. Member-facing screens use Collect IDs and safe payment status.',
  ),
  CollectPolicySection(
    title: 'Sharing',
    body:
        'We share only what is needed with service providers that operate authentication, hosting, storage, messaging, support, analytics, or payment verification. We do not sell personal data.',
  ),
  CollectPolicySection(
    title: 'Choices and retention',
    body:
        'You can update your MoMo account, request account deletion, leave groups where supported, and contact support for correction requests. Ledger records may be retained where needed for audit, security, dispute, and legal reasons.',
  ),
];

const collectDefaultTermsSections = [
  CollectPolicySection(
    title: 'Using Collect',
    body:
        'Collect helps groups organize contributions, create payment requests, scan or share group QR codes, and maintain a verified contribution ledger. You must use accurate group, receiver, and payment information.',
  ),
  CollectPolicySection(
    title: 'MoMo payments',
    body:
        'Payments are approved outside Collect through MoMo or the mobile money flow shown on your device. Collect does not ask for payment credentials or sign-in secrets.',
  ),
  CollectPolicySection(
    title: 'Group ownership',
    body:
        'Group owners are responsible for group profile details, receiver setup, recurring settings, member management, and permission readiness. Android SMS access may be required for owner-side payment verification.',
  ),
  CollectPolicySection(
    title: 'Disputes and corrections',
    body:
        'If a payment is missing, duplicated, incorrect, or needs review, contact support. Collect may use payment status, transaction references, SMS evidence, and audit logs to investigate.',
  ),
  CollectPolicySection(
    title: 'Acceptable use',
    body:
        'Do not create misleading groups, impersonate another person, abuse QR links, submit false payment claims, or use Collect to request illegal or unauthorized payments.',
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
    required this.ussdCode,
    required this.ussdDisplayCode,
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
    ussdCode: collectDefaultUssdCode,
    ussdDisplayCode: collectDefaultUssdCode,
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
  final String ussdCode;
  final String ussdDisplayCode;

  factory CollectRuntimeConfig.fromJson(Map<String, dynamic> json) {
    final brand = _mapValue(json['brand']);
    final supportChannels = _mapList(json['support_channels']);
    final paymentEntrypoints = _mapList(json['payment_entrypoints']);
    final whatsApp = _firstByKey(supportChannels, 'support.whatsapp');
    final email = _firstByKey(supportChannels, 'support.email');
    final ussd = paymentEntrypoints.firstWhere(
      (item) => item['key'] == 'rw.mtn_momo.ussd.collect_2000',
      orElse: () => const <String, dynamic>{},
    );
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
      ussdCode: _nonEmpty(ussd['code'], defaults.ussdCode),
      ussdDisplayCode: _nonEmpty(
        ussd['display_code'],
        _nonEmpty(ussd['code'], defaults.ussdDisplayCode),
      ),
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

@immutable
class CollectProfile {
  const CollectProfile({
    required this.id,
    required this.publicId,
    required this.whatsappPhone,
    this.momoNumber,
    this.momoPayCode,
  });

  final String id;
  final String publicId;
  final String whatsappPhone;
  final String? momoNumber;
  final String? momoPayCode;

  factory CollectProfile.fromJson(Map<String, dynamic> json) {
    return CollectProfile(
      id: json['id'] as String,
      publicId: json['public_id'] as String,
      whatsappPhone: (json['whatsapp_phone'] as String?) ?? '',
      momoNumber: _localMomoNumber(json['momo_number'] as String?),
      momoPayCode: json['momo_pay_code'] as String?,
    );
  }

  String get safeAlias => 'Collect ID $publicId';

  CollectProfile copyWith({
    Object? momoNumber = _unsetProfileField,
    Object? momoPayCode = _unsetProfileField,
  }) {
    return CollectProfile(
      id: id,
      publicId: publicId,
      whatsappPhone: whatsappPhone,
      momoNumber: identical(momoNumber, _unsetProfileField)
          ? this.momoNumber
          : momoNumber as String?,
      momoPayCode: identical(momoPayCode, _unsetProfileField)
          ? this.momoPayCode
          : momoPayCode as String?,
    );
  }
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
    this.imageUrl,
    this.accentColorHex,
    this.isPublic = false,
    this.recurringCadence = 'monthly',
    this.suggestedAmountRwf,
    this.diasporaEnabled = false,
    this.diasporaRegions = const [],
    this.moderationStatus = 'not_requested',
    required this.createdAt,
  });

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
  final String? imageUrl;
  final String? accentColorHex;
  final bool isPublic;
  final String recurringCadence;
  final int? suggestedAmountRwf;
  final bool diasporaEnabled;
  final List<String> diasporaRegions;
  final String moderationStatus;
  final DateTime createdAt;

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
      creatorUserId: json['creator_user_id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      collectionType: CollectionType.fromJson(
        json['collection_type'] ?? json['category'],
      ),
      categorySubtype: json['category_subtype'] as String?,
      purposeLabel: json['purpose_label'] as String?,
      receiverMomoNumber: _localMomoUnlessCode(
        (receiver?['momo_number'] as String?) ??
            json['receiver_momo_number'] as String?,
        receiverDisplayLabel,
      ),
      receiverDisplayLabel: receiverDisplayLabel,
      imageUrl:
          (json['image_url'] as String?) ??
          (json['cover_image_url'] as String?) ??
          (json['photo_url'] as String?),
      accentColorHex:
          (json['accent_color_hex'] as String?) ??
          (json['card_color_hex'] as String?) ??
          (json['color_hex'] as String?),
      isPublic: _collectionIsPublic(json),
      recurringCadence:
          (json['recurring_cadence'] as String?) ??
          (json['contribution_frequency'] as String?) ??
          (json['frequency'] as String?) ??
          'monthly',
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
    String? imageUrl,
    String? accentColorHex,
    bool? isPublic,
    String? recurringCadence,
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
      imageUrl: imageUrl ?? this.imageUrl,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      isPublic: isPublic ?? this.isPublic,
      recurringCadence: recurringCadence ?? this.recurringCadence,
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
}

@immutable
class PaymentIntentModel {
  const PaymentIntentModel({
    required this.id,
    required this.collectionId,
    required this.expectedAmountRwf,
    required this.receiverMomoNumber,
    this.receiverLabel = 'Primary MoMo receiver',
    this.network = 'unknown',
    this.senderPhoneHash,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String collectionId;
  final int expectedAmountRwf;
  final String receiverMomoNumber;
  final String receiverLabel;
  final String network;
  final String? senderPhoneHash;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory PaymentIntentModel.fromJson(Map<String, dynamic> json) {
    final receiverLabel =
        (json['receiver_label'] as String?) ?? 'Primary MoMo receiver';
    return PaymentIntentModel(
      id: json['id'] as String,
      collectionId: json['collection_id'] as String,
      expectedAmountRwf: (json['expected_amount_rwf'] as num?)?.toInt() ?? 0,
      receiverMomoNumber:
          _localMomoUnlessCode(
            (json['receiver_momo_number'] as String?) ??
                (json['receiver_momo_number_hash'] as String? ?? ''),
            receiverLabel,
          ) ??
          '',
      receiverLabel: receiverLabel,
      network: (json['network'] as String?) ?? 'unknown',
      senderPhoneHash: json['sender_phone_hash'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      createdAt: _dateTime(json['created_at']),
      expiresAt: _dateTime(json['expires_at']),
    );
  }
}

String? _localMomoUnlessCode(String? value, String label) {
  if (value == null || value.trim().isEmpty) return value;
  if (label.trim().toLowerCase().contains('code')) return value.trim();
  return _localMomoNumber(value);
}

String? _localMomoNumber(String? value) {
  if (value == null || value.trim().isEmpty) return value;
  return PhoneNormalizer.tryNormalizeMtnMomoLocal(value) ?? value.trim();
}

@immutable
class Contribution {
  const Contribution({
    required this.id,
    required this.collectionId,
    required this.amountRwf,
    required this.supporterLabel,
    required this.createdAt,
    this.transactionId,
  });

  final String id;
  final String collectionId;
  final int amountRwf;
  final String supporterLabel;
  final DateTime createdAt;
  final String? transactionId;

  factory Contribution.fromJson(Map<String, dynamic> json) {
    return Contribution(
      id: (json['payment_id'] as String?) ?? json['id'] as String,
      collectionId: json['collection_id'] as String,
      amountRwf: (json['amount_rwf'] as num).toInt(),
      supporterLabel:
          (json['supporter_label'] as String?) ??
          (json['contributor_public_id'] == null
              ? 'Collect member'
              : 'Collect ID ${json['contributor_public_id']}'),
      createdAt: _dateTime(json['posted_at'] ?? json['created_at']),
      transactionId: json['transaction_id'] as String?,
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
      senderLabel: 'MoMo SMS',
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
  });

  final int amountRaisedRwf;
  final int supporterCount;
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
