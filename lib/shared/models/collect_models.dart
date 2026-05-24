import 'package:flutter/foundation.dart';

const collectCategories = <String>[
  'Church',
  'Artist / Creator',
  'Sports team',
  'Wedding',
  'Funeral',
  'Medical support',
  'School / education',
  'Community event',
  'Public figure / fan support',
  'Family / friends',
  'Other',
];

@immutable
class CollectProfile {
  const CollectProfile({
    required this.id,
    required this.publicId,
    required this.whatsappPhone,
    this.displayName,
    this.avatarUrl,
    this.momoNumber,
    this.anonymityDefault = 'anonymous',
  });

  final String id;
  final String publicId;
  final String whatsappPhone;
  final String? displayName;
  final String? avatarUrl;
  final String? momoNumber;
  final String anonymityDefault;

  factory CollectProfile.fromJson(Map<String, dynamic> json) {
    return CollectProfile(
      id: json['id'] as String,
      publicId: json['public_id'] as String,
      whatsappPhone: (json['whatsapp_phone'] as String?) ?? '',
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      momoNumber: json['momo_number'] as String?,
      anonymityDefault: (json['anonymity_default'] as String?) ?? 'anonymous',
    );
  }

  String get safeAlias {
    final name = displayName?.trim();
    if (anonymityDefault == 'display_name' && name != null && name.isNotEmpty) {
      return name;
    }
    if (anonymityDefault == 'public_id') return 'User #$publicId';
    return 'Anonymous supporter';
  }

  CollectProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? momoNumber,
    String? anonymityDefault,
  }) {
    return CollectProfile(
      id: id,
      publicId: publicId,
      whatsappPhone: whatsappPhone,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      momoNumber: momoNumber ?? this.momoNumber,
      anonymityDefault: anonymityDefault ?? this.anonymityDefault,
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
    required this.category,
    this.coverImageUrl,
    this.targetAmountRwf,
    this.deadlineAt,
    this.visibility = 'private',
    this.publicStatus = 'private',
    this.isRecurring = false,
    this.recurringRule,
    this.allowAnonymous = true,
    this.contributionVisibility = 'public_safe',
    this.receiverMomoNumber,
    this.receiverDisplayLabel = 'Primary MOMO receiver',
    required this.createdAt,
  });

  final String id;
  final String slug;
  final String creatorUserId;
  final String title;
  final String description;
  final String category;
  final String? coverImageUrl;
  final int? targetAmountRwf;
  final DateTime? deadlineAt;
  final String visibility;
  final String publicStatus;
  final bool isRecurring;
  final Map<String, Object?>? recurringRule;
  final bool allowAnonymous;
  final String contributionVisibility;
  final String? receiverMomoNumber;
  final String receiverDisplayLabel;
  final DateTime createdAt;

  factory CollectCollection.fromJson(Map<String, dynamic> json) {
    final receivers = json['collection_receivers'];
    Map<String, dynamic>? receiver;
    if (receivers is List && receivers.isNotEmpty) {
      receiver = Map<String, dynamic>.from(receivers.first as Map);
    }
    return CollectCollection(
      id: json['id'] as String,
      slug: json['slug'] as String,
      creatorUserId: json['creator_user_id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      category: json['category'] as String,
      coverImageUrl: json['cover_image_url'] as String?,
      targetAmountRwf: (json['target_amount_rwf'] as num?)?.toInt(),
      deadlineAt: _dateTimeOrNull(json['deadline_at']),
      visibility: (json['visibility'] as String?) ?? 'private',
      publicStatus: (json['public_status'] as String?) ?? 'private',
      isRecurring: (json['is_recurring'] as bool?) ?? false,
      recurringRule: _mapOrNull(json['recurring_rule']),
      allowAnonymous: (json['allow_anonymous'] as bool?) ?? true,
      contributionVisibility:
          (json['contribution_visibility'] as String?) ?? 'public_safe',
      receiverMomoNumber:
          (receiver?['momo_number'] as String?) ??
          json['receiver_momo_number'] as String?,
      receiverDisplayLabel:
          (receiver?['label'] as String?) ??
          (json['receiver_display_label'] as String?) ??
          'Primary MOMO receiver',
      createdAt: _dateTime(json['created_at']),
    );
  }

  bool get isPublicApproved => publicStatus == 'public_approved';
  bool get isPrivate => visibility == 'private';

  CollectCollection copyWith({
    String? visibility,
    String? publicStatus,
    String? receiverMomoNumber,
    String? receiverDisplayLabel,
    String? coverImageUrl,
  }) {
    return CollectCollection(
      id: id,
      slug: slug,
      creatorUserId: creatorUserId,
      title: title,
      description: description,
      category: category,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      targetAmountRwf: targetAmountRwf,
      deadlineAt: deadlineAt,
      visibility: visibility ?? this.visibility,
      publicStatus: publicStatus ?? this.publicStatus,
      isRecurring: isRecurring,
      recurringRule: recurringRule,
      allowAnonymous: allowAnonymous,
      contributionVisibility: contributionVisibility,
      receiverMomoNumber: receiverMomoNumber ?? this.receiverMomoNumber,
      receiverDisplayLabel: receiverDisplayLabel ?? this.receiverDisplayLabel,
      createdAt: createdAt,
    );
  }
}

@immutable
class PaymentIntentDraft {
  const PaymentIntentDraft({
    required this.collectionId,
    required this.amountRwf,
    required this.anonymityChoice,
    this.senderPhone,
  });

  final String collectionId;
  final int amountRwf;
  final String anonymityChoice;
  final String? senderPhone;
}

@immutable
class PaymentIntentModel {
  const PaymentIntentModel({
    required this.id,
    required this.collectionId,
    required this.contributionCode,
    required this.expectedAmountRwf,
    required this.receiverMomoNumber,
    this.receiverLabel = 'Primary MOMO receiver',
    this.network = 'unknown',
    this.instructionTitle = 'Mobile money USSD',
    this.instructionBody,
    required this.status,
    required this.anonymityChoice,
    this.reportedTransactionId,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String collectionId;
  final String contributionCode;
  final int expectedAmountRwf;
  final String receiverMomoNumber;
  final String receiverLabel;
  final String network;
  final String instructionTitle;
  final String? instructionBody;
  final String status;
  final String anonymityChoice;
  final String? reportedTransactionId;
  final DateTime createdAt;
  final DateTime expiresAt;

  factory PaymentIntentModel.fromJson(Map<String, dynamic> json) {
    return PaymentIntentModel(
      id: json['id'] as String,
      collectionId: json['collection_id'] as String,
      contributionCode: json['contribution_code'] as String,
      expectedAmountRwf: (json['expected_amount_rwf'] as num?)?.toInt() ?? 0,
      receiverMomoNumber:
          (json['receiver_momo_number'] as String?) ??
          (json['receiver_momo_number_hash'] as String? ?? ''),
      receiverLabel:
          (json['receiver_label'] as String?) ?? 'Primary MOMO receiver',
      network: (json['network'] as String?) ?? 'unknown',
      instructionTitle:
          (json['instruction_title'] as String?) ?? 'Mobile money USSD',
      instructionBody: json['instruction_body'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      anonymityChoice: (json['anonymity_choice'] as String?) ?? 'anonymous',
      reportedTransactionId: json['reported_transaction_id'] as String?,
      createdAt: _dateTime(json['created_at']),
      expiresAt: _dateTime(json['expires_at']),
    );
  }
}

@immutable
class CollectionInvite {
  const CollectionInvite({
    required this.id,
    required this.collectionId,
    required this.inviteToken,
    required this.role,
    required this.expiresAt,
    this.invitedTarget,
  });

  final String id;
  final String collectionId;
  final String inviteToken;
  final String role;
  final DateTime expiresAt;
  final String? invitedTarget;

  factory CollectionInvite.fromJson(
    Map<String, dynamic> json, {
    required String collectionId,
    String? invitedTarget,
  }) {
    return CollectionInvite(
      id: json['id'] as String,
      collectionId: collectionId,
      inviteToken:
          (json['invite_token'] as String?) ??
          (json['invite_token_hash'] as String? ?? ''),
      role: (json['role'] as String?) ?? 'member',
      expiresAt: _dateTime(json['expires_at']),
      invitedTarget: invitedTarget,
    );
  }
}

@immutable
class Contribution {
  const Contribution({
    required this.id,
    required this.collectionId,
    required this.amountRwf,
    required this.supporterLabel,
    required this.anonymityChoice,
    required this.createdAt,
    this.transactionId,
  });

  final String id;
  final String collectionId;
  final int amountRwf;
  final String supporterLabel;
  final String anonymityChoice;
  final DateTime createdAt;
  final String? transactionId;

  factory Contribution.fromJson(Map<String, dynamic> json) {
    return Contribution(
      id: (json['payment_id'] as String?) ?? json['id'] as String,
      collectionId: json['collection_id'] as String,
      amountRwf: (json['amount_rwf'] as num).toInt(),
      supporterLabel:
          (json['supporter_label'] as String?) ?? 'Anonymous supporter',
      anonymityChoice: (json['anonymity_choice'] as String?) ?? 'anonymous',
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
      senderLabel: (json['sender_name'] as String?) ?? 'Unknown sender',
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

DateTime _dateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value == null) return null;
  return _dateTime(value);
}

Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}
