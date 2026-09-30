import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Synthetic local cache fixtures only. No account, server, SMS or payment call.
Map<String, dynamic> _snapshotPayload() => CollectOfflineSnapshot(
  savedAt: DateTime.utc(2026, 1, 1),
  currentProfile: null,
  collections: [
    for (final id in ['healthy-group', 'damaged-group'])
      CollectCollection(
        id: id,
        slug: id,
        creatorUserId: 'synthetic-owner',
        title: id,
        description: 'Summary recovery fixture',
        createdAt: DateTime.utc(2026, 1, 1),
        primaryPaymentRail: 'rwanda_momo',
      ),
  ],
  paymentIntents: const [],
  contributions: const [],
  collectionSummaries: const {
    'healthy-group': CollectionSummary(
      amountRaisedRwf: 5000,
      currentUserBalanceRwf: 1000,
      supporterCount: 4,
    ),
  },
).toJson();

Map<String, dynamic> _withDamagedSummary(Object? value) {
  final payload = _snapshotPayload();
  final summaries = Map<String, dynamic>.from(
    payload['collection_summaries'] as Map,
  );
  summaries['damaged-group'] = value;
  payload['collection_summaries'] = summaries;
  return payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final malformed = <String, Object?>{
    'missing legacy balance': {'currency': 'RWF', 'amount_raised_rwf': 500},
    'fractional legacy total': {
      'currency': 'RWF',
      'amount_raised_minor': 1.25,
      'current_user_balance_minor': 0,
    },
    'invalid count': {
      'currency': 'RWF',
      'amount_raised_minor': 500,
      'current_user_balance_minor': 0,
      'supporter_count': -1,
    },
    'invalid currency metadata': {
      'currency': 4,
      'amount_raised_minor': 500,
      'current_user_balance_minor': 0,
    },
    'null modern balances': {'currency': 'RWF', 'balances': null},
    'malformed modern row': {
      'currency': 'RWF',
      'balances': [false],
    },
    'non-string field key': <Object, Object>{42: 'bad'},
    'non-map summary': 123,
    'null summary': null,
  };
  for (final entry in malformed.entries) {
    test('${entry.key} omits only the damaged aggregate', () {
      final restored = CollectOfflineSnapshot.fromJson(
        _withDamagedSummary(entry.value),
      );
      expect(restored.collections.map((group) => group.id), [
        'healthy-group',
        'damaged-group',
      ]);
      expect(restored.collectionSummaries.keys, ['healthy-group']);
      expect(
        restored.collectionSummaries['healthy-group']!.amountRaisedRwf,
        5000,
      );
      expect(restored.savedAt, DateTime.utc(2026, 1, 1));
      expect(restored.hasReadableData, isTrue);
    });
  }
  test('all unavailable summaries still preserve cached groups', () {
    final payload = _snapshotPayload()
      ..['collection_summaries'] = {
        'healthy-group': {'currency': 'RWF'},
        'damaged-group': {'currency': 'RWF'},
      };
    final restored = CollectOfflineSnapshot.fromJson(payload);
    expect(restored.collections, hasLength(2));
    expect(restored.collectionSummaries, isEmpty);
    expect(restored.hasReadableData, isTrue);
  });
  test('a valid explicit zero aggregate is retained', () {
    final restored = CollectOfflineSnapshot.fromJson(
      _withDamagedSummary({
        'currency': 'RWF',
        'amount_raised_rwf': 0,
        'current_user_balance_rwf': 0,
        'supporter_count': 0,
      }),
    );
    expect(restored.collectionSummaries['damaged-group']!.amountRaisedRwf, 0);
    expect(restored.collectionSummaries['damaged-group']!.supporterCount, 0);
  });
  test('known legacy total with omitted count remains available', () {
    final restored = CollectOfflineSnapshot.fromJson(
      _withDamagedSummary({
        'currency': 'RWF',
        'amount_raised_minor': 900,
        'current_user_balance_minor': 300,
      }),
    );
    final summary = restored.collectionSummaries['damaged-group']!;
    expect(summary.amountRaisedRwf, 900);
    expect(summary.supporterCount, isNull);
  });
  test('valid summaries survive a full snapshot round trip', () {
    final first = CollectOfflineSnapshot.fromJson(_snapshotPayload());
    final second = CollectOfflineSnapshot.fromJson(first.toJson());
    expect(second.savedAt, first.savedAt);
    expect(
      second.collections.map((group) => group.id),
      first.collections.map((group) => group.id),
    );
    final summary = second.collectionSummaries['healthy-group']!;
    expect(summary.amountRaisedRwf, 5000);
    expect(summary.currentUserBalanceRwf, 1000);
    expect(summary.supporterCount, 4);
  });
  test('input maps are not mutated during summary recovery', () {
    final payload = _withDamagedSummary({'currency': 'RWF'});
    final before = jsonEncode(payload);
    CollectOfflineSnapshot.fromJson(payload);
    expect(jsonEncode(payload), before);
  });
  test('summary recovery does not hide invalid non-summary records', () {
    final payload = _snapshotPayload()..['collections'] = [42];
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsA(isA<TypeError>()),
    );
  });
  test(
    'cache read preserves other data and persists only validated aggregates',
    () async {
      const key = 'synthetic.summary-decoding.snapshot';
      final payload = _withDamagedSummary({'currency': 'RWF'});
      SharedPreferences.setMockInitialValues({
        key: jsonEncode(payload),
        'unrelated-setting': 'keep',
      });
      const cache = CollectOfflineCache(preferencesKey: key);
      final restored = await cache.read();
      expect(restored, isNotNull);
      expect(restored!.collections, hasLength(2));
      expect(restored.collectionSummaries.keys, ['healthy-group']);
      expect(restored.savedAt, DateTime.utc(2026, 1, 1));
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('unrelated-setting'), 'keep');
      final persisted = jsonDecode(preferences.getString(key)!) as Map;
      expect((persisted['collection_summaries'] as Map).keys, [
        'healthy-group',
      ]);
      expect(persisted['collections'], hasLength(2));
      final again = await cache.read();
      expect(
        again!.collectionSummaries['healthy-group']!.amountRaisedRwf,
        5000,
      );
    },
  );
}
