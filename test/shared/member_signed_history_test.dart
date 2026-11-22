import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/models/contribution_record_copy.dart';
import 'package:collect_app/shared/models/member_history_page.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const revision = '0123456789abcdef0123456789abcdef';
String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> event(
  int n, {
  Object amount = 1000,
  String kind = 'contribution',
  int? reverses,
  bool own = true,
}) => {
  'entry_id': uuid(n),
  'payment_id': uuid(100),
  'collection_id': uuid(200),
  'group_title': 'Member group',
  'amount_minor': amount,
  'currency': 'RWF',
  'rail': 'rwanda_momo',
  'posted_at': DateTime.utc(2026, 10, 16, 12, n).toIso8601String(),
  'supporter_label': '123456',
  'is_current_user_contribution': own,
  'entry_kind': kind,
  'reverses_entry_id': reverses == null ? null : uuid(reverses),
  'evidence_id': uuid(300),
  'payment_status': 'reversed',
  'provider_confirmation': false,
  'settlement_status': 'not_asserted',
};
Map<String, dynamic> wire(
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>>? complete,
  bool more = false,
}) {
  final all = complete ?? items;
  var credit = 0, debit = 0, ownCredit = 0, ownDebit = 0;
  final ownIds = <String>{};
  for (final row in all) {
    final amount = row['amount_minor'] as int;
    if (amount > 0) {
      credit += amount;
    } else {
      debit -= amount;
    }
    if (row['is_current_user_contribution'] == true) {
      if (amount > 0) {
        ownCredit += amount;
      } else {
        ownDebit -= amount;
      }
      ownIds.add(row['collection_id'] as String);
    }
  }
  return {
    'contract_version': 2,
    'contribution_basis': 'reconciled_evidence_entries',
    'items': items,
    'total_count': all.length,
    'totals': {'RWF': credit - debit},
    'own_totals': {'RWF': ownCredit - ownDebit},
    'credit_totals': {'RWF': credit},
    'debit_totals': {'RWF': debit},
    'own_credit_totals': {'RWF': ownCredit},
    'own_debit_totals': {'RWF': ownDebit},
    'own_collection_ids': ownIds.toList(),
    'revision': revision,
    'next_cursor': more
        ? {'revision': revision, 'after': items.last['entry_id']}
        : null,
  };
}

MemberHistoryPage decode(Map<String, dynamic> json) =>
    MemberHistoryPage.fromJson(json, [
      for (final row in json['items'] as List)
        Contribution.historyEventFromJson(
          Map<String, dynamic>.from(row as Map),
        ),
    ]);

void main() {
  test(
    'full reversal preserves two events for one payment and exact net zero',
    () {
      final page = decode(
        wire([
          event(2, amount: -1000, kind: 'reversal', reverses: 1),
          event(1),
        ]),
      );
      page.validateRequest(query: const MemberHistoryQuery());
      expect(page.items.map((row) => row.id).toSet().length, 2);
      expect(page.items.map((row) => row.paymentId).toSet(), {uuid(100)});
      expect(page.totals, {'RWF': 0});
      expect(page.ownTotals, {'RWF': 0});
      expect(page.creditTotals, {'RWF': 1000});
      expect(page.debitTotals, {'RWF': 1000});
      expect(page.ownCollectionIds, {uuid(200)});
    },
  );
  test('reversal-first page prefix is bounded by gross rather than net', () {
    final all = [
      event(2, amount: -1000, kind: 'reversal', reverses: 1),
      event(1),
    ];
    final first = decode(wire([all.first], complete: all, more: true));
    first.validateRequest(query: const MemberHistoryQuery());
    final next = decode(wire([all.last], complete: all));
    final joined = first.append(next, query: const MemberHistoryQuery());
    expect(joined.items.length, 2);
    expect(joined.totals['RWF'], 0);
    expect(joined.nextCursor, isNull);
  });
  test(
    'filtered negative-only history can complete without the original row',
    () {
      final page = decode(
        wire([event(2, amount: -1000, kind: 'correction', reverses: 1)]),
      );
      page.validateRequest(query: MemberHistoryQuery(search: uuid(2)));
      expect(page.totals, {'RWF': -1000});
      expect(page.creditTotals, {'RWF': 0});
      expect(page.debitTotals, {'RWF': 1000});
    },
  );
  test('separate gross counters preserve exact maximum transport amounts', () {
    const amount = 9007199254740991;
    final page = decode(
      wire([
        event(2, amount: -amount, kind: 'reversal', reverses: 1),
        event(1, amount: amount),
      ]),
    );
    expect(page.totals, {'RWF': 0});
    expect(page.creditTotals['RWF'], amount);
    expect(page.debitTotals['RWF'], amount);
  });
  test(
    'legacy contribution parser still refuses negative and zero amounts',
    () {
      for (final value in [-1000, 0]) {
        expect(
          () => Contribution.fromJson({
            'payment_id': 'legacy-payment',
            'collection_id': 'legacy-group',
            'amount_minor': value,
            'posted_at': '2026-10-16T12:00:00Z',
          }),
          throwsFormatException,
        );
      }
    },
  );
  test('unknown or noninteger history versions are denied', () {
    for (final value in [0, 3, 2.0, '2']) {
      expect(
        () => decode({
          ...wire([event(1)]),
          'contract_version': value,
        }),
        throwsFormatException,
      );
    }
  });
  test(
    'all signed event fields are required, including explicit null lineage',
    () {
      final original = event(1);
      for (final field in original.keys) {
        final damaged = {...original}..remove(field);
        expect(
          () => Contribution.historyEventFromJson(damaged),
          throwsFormatException,
          reason: field,
        );
      }
    },
  );
  test(
    'signed event rejects aliases, malformed lineage and unsupported finality',
    () {
      final bad = <Map<String, dynamic>>[
        {...event(1), 'amount_rwf': 1000},
        {...event(1), 'provider_confirmation': true},
        {...event(1), 'settlement_status': 'confirmed'},
        {...event(1), 'payment_status': 'settled'},
        {...event(1), 'payment_status': 'pending'},
        {...event(1), 'supporter_label': 'A personal name'},
        {...event(1), 'entry_id': 'not-an-event-id'},
        {...event(1), 'is_current_user_contribution': 1},
        {...event(1), 'amount_minor': 0},
        {...event(1), 'amount_minor': -1},
        {...event(1), 'amount_minor': 1.5},
        {...event(1), 'amount_minor': 9007199254740992},
        {...event(1), 'amount_minor': -9007199254740992},
        {...event(1), 'amount_minor': double.nan},
        {...event(1), 'entry_kind': 'correction'},
        {...event(1), 'reverses_entry_id': uuid(2)},
        event(2, amount: -1000, kind: 'reversal', reverses: 2),
      ];
      for (final json in bad) {
        expect(
          () => Contribution.historyEventFromJson(json),
          throwsFormatException,
        );
      }
      expect(
        Contribution.historyEventFromJson({
          ...event(1),
          'supporter_label': 'Member',
        }).supporterLabel,
        'Member',
      );
    },
  );
  test('duplicate event IDs and multiple compensations cannot be merged', () {
    expect(() => decode(wire([event(1), event(1)])), throwsFormatException);
    expect(
      () => decode(
        wire([
          event(3, amount: -1000, kind: 'correction', reverses: 1),
          event(2, amount: -1000, kind: 'reversal', reverses: 1),
        ]),
      ),
      throwsFormatException,
    );
  });
  test(
    'present original must agree with payment, evidence and compensation amount',
    () {
      for (final change in [
        {'payment_id': uuid(101)},
        {'evidence_id': uuid(301)},
        {'amount_minor': -999},
        {'is_current_user_contribution': false},
      ]) {
        expect(
          () => decode(
            wire([
              {
                ...event(2, amount: -1000, kind: 'reversal', reverses: 1),
                ...change,
              },
              event(1),
            ]),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('gross totals and own counters cannot overclaim a complete page', () {
    final valid = wire([
      event(2, amount: -1000, kind: 'reversal', reverses: 1),
      event(1),
    ]);
    for (final patch in [
      {
        'credit_totals': {'RWF': 2000},
        'totals': {'RWF': 1000},
      },
      {
        'own_credit_totals': {'RWF': 1001},
        'own_totals': {'RWF': 1},
      },
      {
        'debit_totals': {'RWF': 999},
        'totals': {'RWF': 1},
      },
      {'own_collection_ids': <String>[]},
      {
        'totals': {'RWF': 0, 'USD': 0},
      },
    ]) {
      expect(() => decode({...valid, ...patch}), throwsFormatException);
    }
  });
  test(
    'continuation rejects changed gross metadata despite same net and revision',
    () {
      final all = [
        event(2, amount: -1000, kind: 'reversal', reverses: 1),
        event(1),
      ];
      final first = decode(wire([all.first], complete: all, more: true));
      final tampered = decode({
        ...wire([all.last], complete: all),
        'credit_totals': {'RWF': 2000},
        'debit_totals': {'RWF': 2000},
      });
      expect(() => first.append(tampered), throwsFormatException);
    },
  );
  test(
    'signed numeric sort and stable entry IDs order distinct payment events',
    () {
      final positive = event(1),
          negative = event(2, amount: -1000, kind: 'reversal', reverses: 1);
      decode(
        wire([positive, negative]),
      ).validateRequest(query: const MemberHistoryQuery(sort: 'highest'));
      decode(
        wire([negative, positive]),
      ).validateRequest(query: const MemberHistoryQuery(sort: 'lowest'));
      expect(
        () => decode(
          wire([negative, positive]),
        ).validateRequest(query: const MemberHistoryQuery(sort: 'highest')),
        throwsFormatException,
      );
    },
  );
  test(
    'v2 snapshot round trip retains signed identity,lineage and gross metadata',
    () {
      final page = decode(
        wire([
          event(2, amount: -1000, kind: 'reversal', reverses: 1),
          event(1),
        ]),
      );
      final snapshot = CollectOfflineSnapshot(
        savedAt: DateTime.utc(2026, 10, 16),
        currentProfile: null,
        collections: const [],
        paymentIntents: const [],
        contributions: page.items,
        historyPage: page,
      );
      final encoded =
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;
      final restored = CollectOfflineSnapshot.fromJson(encoded);
      expect(restored.historyPage!.metadata, page.metadata);
      expect(restored.contributions.first.amountMinor, -1000);
      expect(restored.contributions.first.paymentId, uuid(100));
      expect(restored.contributions.first.reversesEntryId, uuid(1));
      expect(restored.contributions.first.id, uuid(2));
      (encoded['contributions'] as List).first.remove('contract_version');
      expect(
        () => CollectOfflineSnapshot.fromJson(encoded),
        throwsFormatException,
      );
    },
  );
  test(
    'member wording distinguishes compensated records without provider claims',
    () {
      final reversal = Contribution.historyEventFromJson(
        event(2, amount: -1000, kind: 'reversal', reverses: 1),
      );
      final correction = Contribution.historyEventFromJson(
        event(2, amount: -1000, kind: 'correction', reverses: 1),
      );
      expect(ContributionRecordCopy.labelFor(reversal), 'Recorded reversal');
      expect(
        ContributionRecordCopy.labelFor(correction),
        'Recorded correction',
      );
      expect(
        ContributionRecordCopy.labelFor(
          Contribution.historyEventFromJson(event(1)),
        ),
        'Recorded contribution',
      );
      expect(reversal.transactionId, isNull);
      expect(
        ContributionRecordCopy.explanation,
        contains('does not verify provider settlement'),
      );
    },
  );
}
