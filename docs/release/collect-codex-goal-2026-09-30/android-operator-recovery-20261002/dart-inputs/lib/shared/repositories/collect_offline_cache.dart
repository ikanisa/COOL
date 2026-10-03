import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/protected_snapshot_store.dart';
import '../../core/data/exact_json_values.dart';
import '../models/collect_models.dart';
import '../models/member_history_page.dart';

class CollectOfflineCache {
  // Kept for synthetic legacy-cache tests and explicit migration adapters only.
  // Production repository construction uses protected() below.
  const CollectOfflineCache({this.preferencesKey = _defaultKey})
    : _protected = false,
      _store = const ProtectedSnapshotStore();

  const CollectOfflineCache.protected({
    this._store = const ProtectedSnapshotStore(),
  }) : preferencesKey = 'collect.protected_snapshot.v5',
       _protected = true;

  final bool _protected;
  final ProtectedSnapshotStore _store;

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

  Future<CollectOfflineSnapshot?> read({String? ownerUserId}) async {
    if (_protected) return _readProtected(ownerUserId);
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
      // Validate structure before legacy geography filtering; malformed rows
      // must never disappear into a fabricated empty financial window.
      for (final field in ['collections', 'payment_intents', 'contributions']) {
        _snapshotRows(payload, field);
      }
      bool rwandaRow(Object? row, {bool collection = false}) {
        if (row is! Map) return false;
        final currency = row[collection ? 'settlement_currency' : 'currency'];
        final rail = row[collection ? 'payment_rail' : 'rail'];
        return (currency == null || currency == 'RWF') &&
            (rail == null || rail == 'rwanda_momo');
      }

      final localPayload = Map<String, dynamic>.from(payload);
      final cachedProfile = payload['current_profile'];
      if (cachedProfile is Map &&
          (cachedProfile['country_code'] != 'RW' ||
              cachedProfile['currency_code'] != 'RWF')) {
        localPayload['current_profile'] = null;
      }
      localPayload['collections'] = [
        for (final row in _list(payload['collections']))
          if (rwandaRow(row, collection: true)) row,
      ];
      localPayload['payment_intents'] = [
        for (final row in _list(payload['payment_intents']))
          if (rwandaRow(row)) row,
      ];
      if (_list(localPayload['payment_intents']).length !=
          _list(payload['payment_intents']).length) {
        localPayload['pending_intent_count'] = null;
      }
      localPayload['contributions'] = [
        for (final row in _list(payload['contributions']))
          if (rwandaRow(row)) row,
      ];
      if (_list(localPayload['contributions']).length !=
          _list(payload['contributions']).length) {
        localPayload['history_page'] = null;
      }
      final cachedHistory = payload['history_page'];
      if (cachedHistory is Map &&
          (_map(cachedHistory['totals']).keys.any((key) => key != 'RWF') ||
              _map(
                cachedHistory['own_totals'],
              ).keys.any((key) => key != 'RWF') ||
              _list(cachedHistory['items']).any((row) => !rwandaRow(row)))) {
        localPayload['history_page'] = null;
      }
      localPayload['collection_summaries'] = {
        for (final entry in _map(payload['collection_summaries']).entries)
          if (entry.value is Map &&
              ((entry.value as Map)['currency'] == null ||
                  (entry.value as Map)['currency'] == 'RWF') &&
              (_list((entry.value as Map)['balances']).isEmpty ||
                  _list(
                    (entry.value as Map)['balances'],
                  ).every((row) => row is Map && row['currency'] == 'RWF')))
            entry.key: entry.value,
      };
      final snapshot = CollectOfflineSnapshot.fromJson(localPayload);
      final sanitized = snapshot.withoutCollections(
        _retiredNonProductionCollectionIds,
      );
      if (epoch != _clearEpochs[preferencesKey]) return null;
      if (sourceKey != preferencesKey ||
          jsonEncode(payload) != jsonEncode(sanitized.toJson()) ||
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

  Future<void> save(CollectOfflineSnapshot snapshot) {
    final epoch = _clearEpochs[preferencesKey];
    return _serialize(() async {
      if (epoch != _clearEpochs[preferencesKey]) return;
      if (_protected) {
        await _removeLegacyPlaintext();
        final owner = snapshot.currentProfile?.id;
        if (owner == null) return;
        await _store.write(owner, jsonEncode(snapshot.toJson()));
      } else {
        await _save(snapshot);
      }
    });
  }

  Future<CollectOfflineSnapshot?> _readProtected(String? owner) async {
    if (owner == null) return null;
    final epoch = _clearEpochs[preferencesKey];
    final pending = _writes[preferencesKey];
    if (pending != null) await pending;
    await _removeLegacyPlaintext();
    if (epoch != _clearEpochs[preferencesKey]) return null;
    final encoded = await _store.read(owner);
    if (encoded == null || epoch != _clearEpochs[preferencesKey]) return null;
    try {
      final data = jsonDecode(encoded);
      if (data is! Map<String, dynamic> || data['version'] != 4) return null;
      final snapshot = CollectOfflineSnapshot.fromJson(data);
      if (snapshot.currentProfile?.id.toLowerCase() != owner.toLowerCase() ||
          snapshot.currentProfile?.countryCode != 'RW' ||
          snapshot.currentProfile?.currencyCode != 'RWF') {
        return null;
      }
      if (epoch != _clearEpochs[preferencesKey]) return null;
      return snapshot.withoutCollections(_retiredNonProductionCollectionIds);
    } on FormatException {
      // Retain ciphertext for investigation, but never display malformed finance.
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> _removeLegacyPlaintext() async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in [
      _defaultKey,
      _completeHistoryCacheKey,
      _singleCurrencyCacheKey,
      _legacyPaymentCacheKey,
    ]) {
      if (preferences.containsKey(key) && !(await preferences.remove(key))) {
        throw StateError('Legacy financial cache could not be removed');
      }
    }
  }

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
    if (_protected) {
      await _store.clear();
      await _removeLegacyPlaintext();
      return;
    }
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
    final collections = [
      for (final row in _snapshotRows(json, 'collections'))
        CollectCollection.fromJson(row),
    ];
    final intents = [
      for (final row in _snapshotRows(json, 'payment_intents'))
        PaymentIntentModel.fromJson(row),
    ];
    final contributions = [
      for (final row in _snapshotRows(json, 'contributions'))
        Contribution.fromJson(row),
    ];
    _uniqueSnapshotIds(collections.map((row) => row.id), 'collections');
    _uniqueSnapshotIds(intents.map((row) => row.id), 'payment_intents');
    _uniqueSnapshotIds(contributions.map((row) => row.id), 'contributions');
    return CollectOfflineSnapshot(
      savedAt: exactJsonTimestamp(json['saved_at'], field: 'snapshot.saved_at'),
      currentProfile: json['current_profile'] == null
          ? null
          : CollectProfile.fromJson(
              _snapshotMap(json['current_profile'], 'current_profile'),
            ),
      collections: List.unmodifiable(collections),
      paymentIntents: List.unmodifiable(intents),
      contributions: List.unmodifiable(contributions),
      historyPage: json['history_page'] == null
          ? null
          : MemberHistoryPage.fromJson(
              _snapshotMap(json['history_page'], 'history_page'),
              contributions,
            ),
      pendingIntentCount: json['pending_intent_count'] == null
          ? null
          : exactJsonInteger(
              json['pending_intent_count'],
              field: 'snapshot.pending_intent_count',
              minimum: 0,
            ),
      collectionSummaries: Map.unmodifiable(
        _cachedCollectionSummaries(json['collection_summaries']),
      ),
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

// An invalid aggregate is unavailable, not zero. Recover other cached groups
// and their valid data rather than letting one summary invalidate the snapshot.
// The live reader still decodes strictly: it never uses this cache-only policy.
Map<String, CollectionSummary> _cachedCollectionSummaries(Object? value) {
  final result = <String, CollectionSummary>{};
  for (final entry in _map(value).entries) {
    final row = entry.value;
    if (row is! Map || row.keys.any((key) => key is! String)) continue;
    try {
      exactJsonIdentifier(entry.key, field: 'snapshot.summary.collection_id');
      result[entry.key] = CollectionSummary.fromJson(
        Map<String, dynamic>.from(row),
      );
    } on FormatException {
      // Drop only this invalid summary. Do not synthesize from partial history,
      // swallow other failures, log private payloads, or change savedAt.
      continue;
    }
  }
  return result;
}

List<Object?> _list(Object? value) {
  return value is List ? value : const [];
}

Map<String, Object?> _map(Object? value) {
  return value is Map
      ? {for (final entry in value.entries) entry.key.toString(): entry.value}
      : const {};
}

Map<String, dynamic> _snapshotMap(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Invalid snapshot field: $field');
  }
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _snapshotRows(
  Map<String, dynamic> json,
  String field,
) {
  // Older explicit migration snapshots may omit a window. That absence conveys
  // no complete aggregate; present malformed data is always denied.
  if (!json.containsKey(field)) return const [];
  final value = json[field];
  if (value is! List) throw FormatException('Invalid snapshot field: $field');
  return [for (final row in value) _snapshotMap(row, field)];
}

void _uniqueSnapshotIds(Iterable<String> ids, String field) {
  final seen = <String>{};
  for (final id in ids) {
    exactJsonIdentifier(id, field: field);
    if (!seen.add(id)) {
      throw FormatException('Duplicate snapshot field: $field');
    }
  }
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
    'momo_pay_code': profile.momoPayCode,
  };
}

Map<String, dynamic> _collectionToJson(CollectCollection collection) {
  return {
    'id': collection.id,
    'slug': collection.slug,
    // Public projections can legitimately omit owner identity. Persist absence
    // as absence rather than an invalid empty immutable identifier.
    'creator_user_id': collection.creatorUserId.isEmpty
        ? null
        : collection.creatorUserId,
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
    'currency': contribution.currency,
    'supporter_label': contribution.supporterLabel,
    'created_at': contribution.createdAt.toUtc().toIso8601String(),
    'transaction_id': null,
    'is_current_user_contribution': contribution.isCurrentUserContribution,
  };
}
