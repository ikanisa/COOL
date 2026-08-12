import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/collect_models.dart';

class CollectOfflineCache {
  const CollectOfflineCache({this.preferencesKey = _defaultKey});

  static const _defaultKey = 'collect.offline_snapshot.v1';
  static const _retiredDeveloperSeedCollectionIds = <String>{
    '8db1f114-4f2b-4a6a-aec9-a0e33a1f1001',
    '8db1f114-4f2b-4a6a-aec9-a0e33a1f1002',
  };

  final String preferencesKey;

  Future<CollectOfflineSnapshot?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(preferencesKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final snapshot = CollectOfflineSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      final sanitized = snapshot.withoutCollections(
        _retiredDeveloperSeedCollectionIds,
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
    await preferences.setString(preferencesKey, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(preferencesKey);
  }
}

class CollectOfflineSnapshot {
  const CollectOfflineSnapshot({
    required this.savedAt,
    required this.currentProfile,
    required this.collections,
    required this.paymentIntents,
    required this.contributions,
  });

  final DateTime savedAt;
  final CollectProfile? currentProfile;
  final List<CollectCollection> collections;
  final List<PaymentIntentModel> paymentIntents;
  final List<Contribution> contributions;

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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
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
    };
  }
}

List<Object?> _list(Object? value) {
  return value is List ? value : const [];
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
    'momo_number': profile.momoNumber,
    'momo_pay_code': profile.momoPayCode,
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
    'receiver_momo_number': collection.receiverMomoNumber,
    'receiver_display_label': collection.receiverDisplayLabel,
    'image_url': collection.imageUrl,
    'accent_color_hex': collection.accentColorHex,
    'is_public': collection.isPublic,
    'recurring_cadence': collection.recurringCadence,
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
    'expected_amount_rwf': intent.expectedAmountRwf,
    'receiver_momo_number': intent.receiverMomoNumber,
    'receiver_label': intent.receiverLabel,
    'network': intent.network,
    'sender_phone_hash': intent.senderPhoneHash,
    'status': intent.status,
    'created_at': intent.createdAt.toUtc().toIso8601String(),
    'expires_at': intent.expiresAt.toUtc().toIso8601String(),
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
  };
}
