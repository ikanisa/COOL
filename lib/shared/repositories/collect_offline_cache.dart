import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/collect_models.dart';

class CollectOfflineCache {
  const CollectOfflineCache({this.preferencesKey = _defaultKey});

  static const _defaultKey = 'collect.offline_snapshot.v2';
  static const _legacyPaymentCacheKey = 'collect.offline_snapshot.v1';
  static const _retiredNonProductionCollectionIds = <String>{
    '8db1f114-4f2b-4a6a-aec9-a0e33a1f1001',
    '8db1f114-4f2b-4a6a-aec9-a0e33a1f1002',
    'bfb5d4d3-cb40-4bf1-ae89-579ea98073d5',
    'd4bc46a2-dd50-4440-b950-dda5a13335d9',
    '9208e94b-8b5a-4588-9dc2-0d4f8a34b7a5',
    '747de065-e492-449c-b4e0-caa857ca413f',
    'e30c018c-d19f-44f3-ada8-d7e666d45c55',
  };

  final String preferencesKey;

  Future<CollectOfflineSnapshot?> read() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferencesKey == _defaultKey) {
      await preferences.remove(_legacyPaymentCacheKey);
    }
    final raw = preferences.getString(preferencesKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final snapshot = CollectOfflineSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      final sanitized = snapshot.withoutCollections(
        _retiredNonProductionCollectionIds,
      );
      if (sanitized.collections.length != snapshot.collections.length ||
          sanitized.paymentIntents.length != snapshot.paymentIntents.length ||
          sanitized.contributions.length != snapshot.contributions.length) {
        await save(sanitized);
      }
      return sanitized;
    } catch (_) {
      await preferences.remove(preferencesKey);
      return null;
    }
  }

  Future<void> save(CollectOfflineSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferencesKey == _defaultKey) {
      await preferences.remove(_legacyPaymentCacheKey);
    }
    await preferences.setString(preferencesKey, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(preferencesKey);
    if (preferencesKey == _defaultKey) {
      await preferences.remove(_legacyPaymentCacheKey);
    }
  }
}

class CollectOfflineSnapshot {
  const CollectOfflineSnapshot({
    required this.savedAt,
    required this.currentProfile,
    required this.collections,
    required this.paymentIntents,
    required this.contributions,
    this.collectionSummaries = const {},
  });

  final DateTime savedAt;
  final CollectProfile? currentProfile;
  final List<CollectCollection> collections;
  final List<PaymentIntentModel> paymentIntents;
  final List<Contribution> contributions;
  final Map<String, CollectionSummary> collectionSummaries;

  bool get hasReadableData {
    return currentProfile != null ||
        collections.isNotEmpty ||
        paymentIntents.isNotEmpty ||
        contributions.isNotEmpty;
  }

  CollectOfflineSnapshot withoutCollections(Set<String> collectionIds) {
    if (collectionIds.isEmpty) return this;
    return CollectOfflineSnapshot(
      savedAt: savedAt,
      currentProfile: currentProfile,
      collections: [
        for (final item in collections)
          if (!collectionIds.contains(item.id)) item,
      ],
      paymentIntents: [
        for (final item in paymentIntents)
          if (!collectionIds.contains(item.collectionId)) item,
      ],
      contributions: [
        for (final item in contributions)
          if (!collectionIds.contains(item.collectionId)) item,
      ],
      collectionSummaries: {
        for (final entry in collectionSummaries.entries)
          if (!collectionIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  factory CollectOfflineSnapshot.fromJson(Map<String, dynamic> json) {
    return CollectOfflineSnapshot(
      savedAt: _dateTime(json['saved_at']),
      currentProfile: json['current_profile'] == null
          ? null
          : CollectProfile.fromJson(
              Map<String, dynamic>.from(json['current_profile'] as Map),
            ),
      collections: [
        for (final row in _list(json['collections']))
          CollectCollection.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      paymentIntents: [
        for (final row in _list(json['payment_intents']))
          PaymentIntentModel.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      contributions: [
        for (final row in _list(json['contributions']))
          Contribution.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      collectionSummaries: {
        for (final entry in _map(json['collection_summaries']).entries)
          if (entry.value is Map)
            entry.key: CollectionSummary.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 2,
      'saved_at': savedAt.toUtc().toIso8601String(),
      'current_profile': currentProfile == null
          ? null
          : _profileToJson(currentProfile!),
      'collections': [for (final item in collections) _collectionToJson(item)],
      'payment_intents': [
        for (final item in paymentIntents) _paymentIntentToJson(item),
      ],
      'contributions': [
        for (final item in contributions) _contributionToJson(item),
      ],
      'collection_summaries': {
        for (final entry in collectionSummaries.entries)
          entry.key: {
            'amount_raised_rwf': entry.value.amountRaisedRwf,
            'supporter_count': entry.value.supporterCount,
            'current_user_balance_rwf': entry.value.currentUserBalanceRwf,
          },
      },
    };
  }
}

List<Object?> _list(Object? value) {
  return value is List ? value : const [];
}

Map<String, Object?> _map(Object? value) {
  return value is Map
      ? {for (final entry in value.entries) entry.key.toString(): entry.value}
      : const {};
}

DateTime _dateTime(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc() ?? DateTime.now().toUtc();
  }
  return DateTime.now().toUtc();
}

Map<String, dynamic> _profileToJson(CollectProfile profile) {
  return {
    'id': profile.id,
    'public_id': profile.publicId,
    'whatsapp_phone': profile.whatsappPhone,
    'display_name': profile.displayName,
    'country_code': profile.countryCode,
    'currency_code': profile.currencyCode,
    'revolut_name': profile.revolutName,
  };
}

Map<String, dynamic> _collectionToJson(CollectCollection collection) {
  return {
    'id': collection.id,
    'slug': collection.slug,
    'creator_user_id': collection.creatorUserId,
    'title': collection.title,
    'description': collection.description,
    'collection_type': collection.collectionType.storageValue,
    'category_subtype': collection.categorySubtype,
    'purpose_label': collection.purposeLabel,
    'receiver_display_label': collection.receiverDisplayLabel,
    'image_url': collection.imageUrl,
    'accent_color_hex': collection.accentColorHex,
    'is_public': collection.isPublic,
    'is_member': collection.isCurrentUserMember,
    'is_recurring': collection.isRecurring,
    'recurring_cadence': collection.recurringCadence,
    'visibility_status': collection.visibilityStatus,
    'suggested_amount_rwf': collection.suggestedAmountRwf,
    'diaspora_enabled': collection.diasporaEnabled,
    'diaspora_regions': collection.diasporaRegions,
    'moderation_status': collection.moderationStatus,
    'created_at': collection.createdAt.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _paymentIntentToJson(PaymentIntentModel intent) {
  return {
    'id': intent.id,
    'collection_id': intent.collectionId,
    'amount_minor': intent.expectedAmountMinor,
    'currency': intent.currency,
    'transfer_reference': intent.transferReference,
    'destination_snapshot': _bankDestinationToJson(intent.destination),
    'status': intent.status,
    'created_at': intent.createdAt.toUtc().toIso8601String(),
    'expires_at': intent.expiresAt.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _bankDestinationToJson(
  BankTransferDestination destination,
) {
  return {
    'id': destination.id,
    'beneficiary_name': destination.beneficiaryName,
    'iban': destination.iban,
    'iban_masked': destination.ibanMasked,
    'bic': destination.bic,
    'bank_name': destination.bankName,
    'currency': destination.currency,
    'transfer_scheme': destination.transferScheme,
    'supports_instant': destination.supportsInstant,
    'status': destination.status,
    'is_placeholder': destination.isPlaceholder,
    'enabled': destination.enabled,
  };
}

Map<String, dynamic> _contributionToJson(Contribution contribution) {
  return {
    'id': contribution.id,
    'collection_id': contribution.collectionId,
    'amount_rwf': contribution.amountRwf,
    'supporter_label': contribution.supporterLabel,
    'created_at': contribution.createdAt.toUtc().toIso8601String(),
    'transaction_id': null,
    'is_current_user_contribution': contribution.isCurrentUserContribution,
  };
}
