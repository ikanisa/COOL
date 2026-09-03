import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/collect_models.dart';
import '../models/member_history_page.dart';

class CollectOfflineCache {
  const CollectOfflineCache({this.preferencesKey = _defaultKey});

  static const _defaultKey = 'collect.offline_snapshot.v4';
  static const _completeHistoryCacheKey = 'collect.offline_snapshot.v3';
  static const _singleCurrencyCacheKey = 'collect.offline_snapshot.v2';
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
  static final Map<String, Future<void>> _writes = {};
  static final Map<String, int> _clearEpochs = {};

  // A sign-out clear must finish after already queued saves, never before them.
  Future<void> _serialize(Future<void> Function() operation) {
    final previous = _writes[preferencesKey];
    final next = previous == null
        ? operation()
        : previous.catchError((Object _) {}).then((_) => operation());
    late final Future<void> tail;
    tail = next.whenComplete(() {
      if (identical(_writes[preferencesKey], tail)) {
        _writes.remove(preferencesKey);
      }
    });
    _writes[preferencesKey] = tail;
    return tail;
  }

  Future<CollectOfflineSnapshot?> read() async {
    final epoch = _clearEpochs[preferencesKey];
    final pending = _writes[preferencesKey];
    if (pending != null) await pending;
    final preferences = await SharedPreferences.getInstance();
    if (epoch != _clearEpochs[preferencesKey]) return null;
    if (preferencesKey == _defaultKey) {
      await preferences.remove(_legacyPaymentCacheKey);
    }
    final sourceKey =
        preferencesKey == _defaultKey && !preferences.containsKey(_defaultKey)
        ? preferences.containsKey(_completeHistoryCacheKey)
              ? _completeHistoryCacheKey
              : _singleCurrencyCacheKey
        : preferencesKey;
    final raw = preferences.getString(sourceKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final cachedProfile = payload['current_profile'];
      final containsLegacyNames =
          cachedProfile is Map &&
          (cachedProfile.containsKey('display_name') ||
              cachedProfile.containsKey('revolut_name'));
      final snapshot = CollectOfflineSnapshot.fromJson(payload);
      final sanitized = snapshot.withoutCollections(
        _retiredNonProductionCollectionIds,
      );
      if (epoch != _clearEpochs[preferencesKey]) return null;
      if (sourceKey != preferencesKey ||
          containsLegacyNames ||
          sanitized.collections.length != snapshot.collections.length ||
          sanitized.paymentIntents.length != snapshot.paymentIntents.length ||
          sanitized.contributions.length != snapshot.contributions.length) {
        await save(sanitized);
      }
      return sanitized;
    } catch (_) {
      await preferences.remove(sourceKey);
      return null;
    }
  }

  Future<void> save(CollectOfflineSnapshot snapshot) =>
      _serialize(() => _save(snapshot));

  Future<void> _save(CollectOfflineSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferencesKey == _defaultKey) {
      await preferences.remove(_legacyPaymentCacheKey);
    }
    final saved = await preferences.setString(
      preferencesKey,
      jsonEncode(snapshot.toJson()),
    );
    if (saved && preferencesKey == _defaultKey) {
      // Older clients must not interpret the new per-currency payload as zero.
      await preferences.remove(_singleCurrencyCacheKey);
      await preferences.remove(_completeHistoryCacheKey);
    }
  }

  Future<void> clear() {
    _clearEpochs.update(
      preferencesKey,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    return _serialize(_clear);
  }

  Future<void> _clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(preferencesKey);
    if (preferencesKey == _defaultKey) {
      await preferences.remove(_legacyPaymentCacheKey);
      await preferences.remove(_singleCurrencyCacheKey);
      await preferences.remove(_completeHistoryCacheKey);
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
    this.historyPage,
    this.pendingIntentCount,
  });

  final DateTime savedAt;
  final CollectProfile? currentProfile;
  final List<CollectCollection> collections;
  final List<PaymentIntentModel> paymentIntents;
  final List<Contribution> contributions;
  final Map<String, CollectionSummary> collectionSummaries;
  final MemberHistoryPage? historyPage;
  final int? pendingIntentCount;

  bool get hasReadableData {
    return currentProfile != null ||
        collections.isNotEmpty ||
        paymentIntents.isNotEmpty ||
        contributions.isNotEmpty;
  }

  CollectOfflineSnapshot withoutCollections(Set<String> collectionIds) {
    if (collectionIds.isEmpty) return this;
    if (historyPage != null &&
        (collections.any((c) => collectionIds.contains(c.id)) ||
            contributions.any((c) => collectionIds.contains(c.collectionId)))) {
      // Complete aggregates cannot be adjusted from only a partial cached page.
      throw const FormatException('Retired groups in paged history cache');
    }
    return CollectOfflineSnapshot(
      savedAt: savedAt,
      currentProfile: currentProfile,
      historyPage: historyPage,
      pendingIntentCount: pendingIntentCount,
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
    final contributions = [
      for (final row in _list(json['contributions']))
        Contribution.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
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
      contributions: contributions,
      historyPage: json['history_page'] == null
          ? null
          : MemberHistoryPage.fromJson(
              Map<String, dynamic>.from(json['history_page'] as Map),
              contributions,
            ),
      pendingIntentCount: json['pending_intent_count'] as int?,
      collectionSummaries: {
        for (final entry in _map(json['collection_summaries']).entries)
          if (entry.value is Map &&
              ((entry.value as Map)['currency'] is String ||
                  (entry.value as Map)['balances'] is List))
            entry.key: CollectionSummary.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            ),
      },
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 4,
      'history_page': historyPage?.metadata,
      'pending_intent_count': pendingIntentCount,
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
            'currency': entry.value.currency,
            'supporter_count': entry.value.supporterCount,
            'balances': [
              for (final total in entry.value.totalsByCurrency.entries)
                {
                  'currency': total.key,
                  'amount_raised_minor': total.value,
                  'current_user_balance_minor':
                      entry.value.ownBalancesByCurrency[total.key] ?? 0,
                },
            ],
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
    'country_code': profile.countryCode,
    'currency_code': profile.currencyCode,
    'momo_provider': profile.momoProvider,
    'momo_number': profile.momoNumber,
    'revolut_link': profile.revolutLink,
    'revolut_account': profile.revolutAccount,
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
    'receiver_network': collection.receiverNetwork,
    'payment_rail': collection.primaryPaymentRail,
    'settlement_currency': collection.settlementCurrency,
    'image_url': collection.imageUrl,
    'accent_color_hex': collection.accentColorHex,
    'is_public': collection.isPublic,
    'is_platform_sponsored': collection.isPlatformSponsored,
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
    'rail': intent.rail,
    'currency': intent.currency,
    'receiver_momo_number': intent.receiverMomoNumber,
    'receiver_momo_number_hash': intent.receiverMomoNumberHash,
    'receiver_label': intent.receiverMomoLabel,
    'network': intent.momoNetwork,
    'sender_phone_hash': intent.senderPhoneHash,
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
    'currency': contribution.currency,
    'supporter_label': contribution.supporterLabel,
    'created_at': contribution.createdAt.toUtc().toIso8601String(),
    'transaction_id': null,
    'is_current_user_contribution': contribution.isCurrentUserContribution,
  };
}
