import 'dart:convert';

import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _group() => {
  'id': 'synthetic-group',
  'slug': 'synthetic-group',
  'creator_user_id': 'synthetic-owner',
  'title': 'Synthetic group',
  'created_at': '2026-09-30T12:00:00+02:00',
};
Map<String, dynamic> _summary({
  Object? total = 100,
  Object? own = 20,
  Object? count = 1,
}) => {
  'supporter_count': count,
  'balances': [
    {
      'currency': 'RWF',
      'amount_raised_minor': total,
      'current_user_balance_minor': own,
    },
  ],
};
Map<String, dynamic> _snapshot() => CollectOfflineSnapshot(
  savedAt: DateTime.utc(2026, 9, 30),
  currentProfile: null,
  collections: [CollectCollection.fromJson(_group())],
  paymentIntents: [
    PaymentIntentModel(
      id: 'synthetic-intent',
      collectionId: 'synthetic-group',
      expectedAmountRwf: 10,
      status: 'pending',
      createdAt: DateTime.utc(2000),
      expiresAt: DateTime.utc(2001),
    ),
  ],
  contributions: [
    Contribution(
      id: 'synthetic-payment',
      collectionId: 'synthetic-group',
      amountRwf: 10,
      supporterLabel: 'You',
      createdAt: DateTime.utc(2000),
      isCurrentUserContribution: false,
    ),
  ],
).toJson();
Map<String, dynamic> _metadata({
  int total = 10,
  int own = 0,
  int count = 1,
  List<String> ownIds = const [],
}) => {
  'total_count': count,
  'totals': {'RWF': total},
  'own_totals': {'RWF': own},
  'own_collection_ids': ownIds,
  'revision': '0123456789abcdef0123456789abcdef',
};
Contribution _payment({bool own = false, int amount = 10}) => Contribution(
  id: 'synthetic-payment',
  collectionId: 'synthetic-group',
  amountRwf: amount,
  supporterLabel: 'You',
  createdAt: DateTime.utc(2000),
  isCurrentUserContribution: own,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('public projection with absent owner survives a cache round trip', () {
    final collection = CollectCollection.fromJson(
      _group()..remove('creator_user_id'),
    );
    final snapshot = CollectOfflineSnapshot(
      savedAt: DateTime.utc(2026, 9, 30),
      currentProfile: null,
      collections: [collection],
      paymentIntents: const [],
      contributions: const [],
    );
    final restored = CollectOfflineSnapshot.fromJson(snapshot.toJson());
    expect(restored.collections.single.id, collection.id);
    expect(restored.collections.single.creatorUserId, isEmpty);
    expect(restored.pendingIntentCount, isNull);
  });
  group('canonical transport values', () {
    test('exact digit strings are compared before conversion', () {
      expect(
        exactJsonInteger(
          '0009007199254740991',
          field: 'count',
          allowDigitString: true,
        ),
        maxExactJsonInteger,
      );
      expect(
        exactJsonInteger(
          '-9007199254740991',
          field: 'amount',
          allowDigitString: true,
        ),
        -maxExactJsonInteger,
      );
      for (final value in [
        '9007199254740992',
        '9007199254740993',
        '-9007199254740992',
        '18446744073709551616',
        '1e3',
        '1.0',
        ' 1',
      ]) {
        expect(
          () => exactJsonInteger(value, field: 'count', allowDigitString: true),
          throwsFormatException,
        );
      }
    });
    for (final value in [
      '2026-02-30T10:00:00Z',
      '2025-02-29T10:00:00Z',
      '2026-04-31T10:00:00+00',
      '2026-09-30T24:00:00Z',
      '2026-09-30T10:00:60Z',
      '2026-09-30T10:00:00+24:00',
      '2026-09-30T10:00:00+02:60',
      '2026-09-30T10:00:00',
      '2026-09-30',
      '2026-09-30T10:00:00.1234567Z',
    ]) {
      test('denies invalid or timezone-free timestamp $value', () {
        expect(
          () => exactJsonTimestamp(value, field: 'time'),
          throwsFormatException,
        );
        final payload = _snapshot()..['saved_at'] = value;
        expect(
          () => CollectOfflineSnapshot.fromJson(payload),
          throwsFormatException,
        );
      });
    }
    test(
      'leap date, PostgreSQL offsets and fractions retain the same instant',
      () {
        for (final value in [
          '2024-02-29T12:00:00.123456+02:00',
          '2024-02-29T12:00:00.123456+0200',
          '2024-02-29T10:00:00.123456+00',
          '2024-02-29T10:00:00.123456Z',
        ]) {
          expect(
            exactJsonTimestamp(value, field: 'time'),
            DateTime.utc(2024, 2, 29, 10, 0, 0, 123, 456),
          );
        }
        final instant = DateTime.fromMillisecondsSinceEpoch(1);
        expect(exactJsonTimestamp(instant, field: 'time'), instant.toUtc());
      },
    );
  });
  group('shared collection contracts', () {
    for (final value in [
      1.5,
      -1,
      0,
      maxExactJsonInteger + 1,
      double.nan,
      double.infinity,
      '10',
    ]) {
      test('suggested amount rejects $value without truncation', () {
        expect(
          () => CollectCollection.fromJson(
            _group()..['suggested_amount_rwf'] = value,
          ),
          throwsFormatException,
        );
      });
    }
    test('optional suggestion and exact maximum remain valid', () {
      expect(CollectCollection.fromJson(_group()).suggestedAmountRwf, isNull);
      final group = CollectCollection.fromJson(
        _group()..['suggested_amount_rwf'] = maxExactJsonInteger,
      );
      expect(group.suggestedAmountRwf, maxExactJsonInteger);
      expect(group.createdAt, DateTime.utc(2026, 9, 30, 10));
    });
    for (final field in ['id', 'slug', 'creator_user_id']) {
      for (final value in ['  hidden', '', 'hidden\nidentifier']) {
        test('group $field denies malformed identity', () {
          expect(
            () => CollectCollection.fromJson(_group()..[field] = value),
            throwsFormatException,
          );
        });
      }
    }
    test('missing or impossible collection time is never current time', () {
      expect(
        () => CollectCollection.fromJson(_group()..remove('created_at')),
        throwsFormatException,
      );
      expect(
        () => CollectCollection.fromJson(
          _group()..['created_at'] = '2026-02-30T10:00:00Z',
        ),
        throwsFormatException,
      );
    });
    for (final value in [
      maxExactJsonInteger + 1,
      -maxExactJsonInteger - 1,
      1.5,
      double.nan,
      double.infinity,
      '100',
    ]) {
      for (final field in ['total', 'own']) {
        test('modern $field amount denies inexact value $value', () {
          expect(
            () => CollectionSummary.fromJson(
              _summary(
                total: field == 'total' ? value : 100,
                own: field == 'own' ? value : 20,
              ),
            ),
            throwsFormatException,
          );
        });
      }
    }
    for (final count in [-1, 1.5, maxExactJsonInteger + 1, '1', true]) {
      test('modern contributor count denies $count', () {
        expect(
          () => CollectionSummary.fromJson(_summary(count: count)),
          throwsFormatException,
        );
      });
    }
    test(
      'modern signed safe boundary and unknown versus explicit zero count',
      () {
        final summary = CollectionSummary.fromJson(
          _summary(
            total: maxExactJsonInteger,
            own: -maxExactJsonInteger,
            count: maxExactJsonInteger,
          ),
        );
        expect(summary.currentUserBalanceRwf, -maxExactJsonInteger);
        expect(summary.supporterCount, maxExactJsonInteger);
        expect(
          CollectionSummary.fromJson(_summary(count: null)).supporterCount,
          isNull,
        );
        expect(
          CollectionSummary.fromJson(
            _summary(total: 0, own: 0, count: 0),
          ).supporterCount,
          0,
        );
        expect(
          CollectionSummary.fromJson(const {
            'balances': [],
            'supporter_count': 0,
          }).amountRaisedRwf,
          0,
        );
      },
    );
  });
  group('cache windows', () {
    for (final field in ['collections', 'payment_intents', 'contributions']) {
      for (final value in [
        false,
        1,
        <String, dynamic>{},
        null,
        [42],
      ]) {
        test(
          '$field malformed structure is denied before migration filtering',
          () async {
            final payload = _snapshot()..[field] = value;
            expect(
              () => CollectOfflineSnapshot.fromJson(payload),
              throwsFormatException,
            );
            const key = 'synthetic.structure.snapshot';
            SharedPreferences.setMockInitialValues({key: jsonEncode(payload)});
            expect(
              await const CollectOfflineCache(preferencesKey: key).read(),
              isNull,
            );
          },
        );
      }
      test('$field duplicate immutable ID is denied without metadata', () {
        final payload = _snapshot();
        final rows = payload[field] as List;
        rows.add(Map<String, dynamic>.from(rows.first as Map));
        expect(
          () => CollectOfflineSnapshot.fromJson(payload),
          throwsFormatException,
        );
      });
    }
    for (final count in [-1, 1.5, maxExactJsonInteger + 1, '1', true]) {
      test('pending cache count rejects $count', () {
        expect(
          () => CollectOfflineSnapshot.fromJson(
            _snapshot()..['pending_intent_count'] = count,
          ),
          throwsFormatException,
        );
      });
    }
    test(
      'unknown pending count clears prior known count instead of retaining it',
      () {
        const state = CollectState(
          currentProfile: null,
          collections: [],
          paymentIntents: [],
          contributions: [],
          pendingIntentCount: 17,
        );
        expect(state.copyWith().pendingIntentCount, 17);
        expect(
          state.copyWith(pendingIntentCount: null).pendingIntentCount,
          isNull,
        );
        expect(state.copyWith(pendingIntentCount: 0).pendingIntentCount, 0);
      },
    );
    test('omitted legacy windows retain unknown aggregates', () {
      final snapshot = CollectOfflineSnapshot.fromJson({
        'saved_at': '2000-01-01T00:00:00+00',
      });
      expect(snapshot.historyPage, isNull);
      expect(snapshot.pendingIntentCount, isNull);
      expect(snapshot.collectionSummaries, isEmpty);
    });
    test('decoded cache collections and windows are immutable', () {
      final snapshot = CollectOfflineSnapshot.fromJson(_snapshot());
      expect(() => snapshot.collections.clear(), throwsUnsupportedError);
      expect(() => snapshot.paymentIntents.clear(), throwsUnsupportedError);
      expect(() => snapshot.contributions.clear(), throwsUnsupportedError);
      expect(snapshot.paymentIntents.single.isAwaitingTransfer, isFalse);
    });
  });
  group('history aggregate consistency', () {
    test('partial page must not exceed the complete aggregate', () {
      expect(
        () => MemberHistoryPage.fromJson(_metadata(total: 9, count: 2), [
          _payment(),
        ]),
        throwsFormatException,
      );
    });
    test('loaded ownership requires matching collection ID and own total', () {
      expect(
        () => MemberHistoryPage.fromJson(_metadata(own: 10, count: 2), [
          _payment(own: true),
        ]),
        throwsFormatException,
      );
      expect(
        () => MemberHistoryPage.fromJson(
          _metadata(own: 9, count: 2, ownIds: ['synthetic-group']),
          [_payment(own: true)],
        ),
        throwsFormatException,
      );
    });
    test('complete history must equal complete totals and ownership IDs', () {
      expect(
        () => MemberHistoryPage.fromJson(_metadata(total: 11), [_payment()]),
        throwsFormatException,
      );
      expect(
        () => MemberHistoryPage.fromJson(
          _metadata(own: 1, ownIds: ['synthetic-group']),
          [_payment()],
        ),
        throwsFormatException,
      );
      expect(
        () => MemberHistoryPage.fromJson(_metadata(ownIds: ['hidden-group']), [
          _payment(),
        ]),
        throwsFormatException,
      );
    });
    test('a display label never grants ownership', () {
      final page = MemberHistoryPage.fromJson(_metadata(), [_payment()]);
      expect(page.items.single.supporterLabel, 'You');
      expect(page.ownCollectionIds, isEmpty);
      expect(page.ownTotals['RWF'], 0);
    });
    test('full page preserves server-owned historical ownership', () {
      final page = MemberHistoryPage.fromJson(
        _metadata(own: 10, ownIds: ['synthetic-group']),
        [_payment(own: true)],
      );
      expect(page.ownTotals['RWF'], 10);
      expect(page.ownCollectionIds, {'synthetic-group'});
    });
    test('ownership IDs cannot contain control characters', () {
      expect(
        () => MemberHistoryPage.fromJson(
          _metadata(count: 2, ownIds: ['hidden\nidentifier']),
          [_payment()],
        ),
        throwsFormatException,
      );
    });
  });
}
