import 'package:flutter/foundation.dart';

@immutable
class CollectProfile {
  const CollectProfile({
    required this.id,
    required this.publicId,
    required this.whatsappPhone,
    this.momoNumber,
  });

  final String id;
  final String publicId;
  final String whatsappPhone;
  final String? momoNumber;

  factory CollectProfile.fromJson(Map<String, dynamic> json) {
    return CollectProfile(
      id: json['id'] as String,
      publicId: json['public_id'] as String,
      whatsappPhone: (json['whatsapp_phone'] as String?) ?? '',
      momoNumber: json['momo_number'] as String?,
    );
  }

  String get safeAlias => 'Collect ID $publicId';

  CollectProfile copyWith({String? momoNumber}) {
    return CollectProfile(
      id: id,
      publicId: publicId,
      whatsappPhone: whatsappPhone,
      momoNumber: momoNumber ?? this.momoNumber,
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
    this.receiverMomoNumber,
    this.receiverDisplayLabel = 'Primary MOMO receiver',
    required this.createdAt,
  });

  final String id;
  final String slug;
  final String creatorUserId;
  final String title;
  final String description;
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

  CollectCollection copyWith({
    String? receiverMomoNumber,
    String? receiverDisplayLabel,
  }) {
    return CollectCollection(
      id: id,
      slug: slug,
      creatorUserId: creatorUserId,
      title: title,
      description: description,
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
    this.receiverLabel = 'Primary MOMO receiver',
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
    return PaymentIntentModel(
      id: json['id'] as String,
      collectionId: json['collection_id'] as String,
      expectedAmountRwf: (json['expected_amount_rwf'] as num?)?.toInt() ?? 0,
      receiverMomoNumber:
          (json['receiver_momo_number'] as String?) ??
          (json['receiver_momo_number_hash'] as String? ?? ''),
      receiverLabel:
          (json['receiver_label'] as String?) ?? 'Primary MOMO receiver',
      network: (json['network'] as String?) ?? 'unknown',
      senderPhoneHash: json['sender_phone_hash'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      createdAt: _dateTime(json['created_at']),
      expiresAt: _dateTime(json['expires_at']),
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

DateTime _dateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  return DateTime.now();
}
