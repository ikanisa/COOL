import 'dart:convert';

import 'package:collect_app/core/data/exact_json_values.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/models/member_history_page.dart';
import 'package:flutter_test/flutter_test.dart';

// The source-bound gate supplies captured genuine SQL receipts through an
// immutable define file. This works in VM and real Chrome without dart:io or
// runtime database/provider access. Synthetic reconciliation inputs prove
// mechanics only; they are not independent provider or device evidence.
const _encoded = String.fromEnvironment('MEMBER_HISTORY_SQL_RECEIPTS_BASE64');

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

MemberHistoryPage _page(Map<String, dynamic> response) =>
    MemberHistoryPage.fromJson(response, [
      for (final row in response['items'] as List)
        Contribution.fromJson(_map(row)),
    ]);

MemberHistoryQuery _query(Map<String, dynamic> value) => MemberHistoryQuery(
  collectionId: value['collection_id'] as String?,
  search: value['search'] as String,
  sort: value['sort'] as String,
);

void main() {
  if (_encoded.isEmpty) {
    test(
      'actual SQL history receipts require the source-bound local packet',
      () {},
      skip:
          'Supply MEMBER_HISTORY_SQL_RECEIPTS_BASE64 through the reviewed gate',
    );
    return;
  }
  final fixture = _map(jsonDecode(utf8.decode(base64Decode(_encoded))));
  final windows = (fixture['pages'] as List).map(_map).toList();
  final balances = (fixture['balances'] as List).map(_map).toList();

  test('actual SQL positive pages decode and match every requested window', () {
    expect(windows.length, greaterThan(20));
    var positive = 0;
    var empty = 0;
    for (final window in windows) {
      final response = _map(window['response']);
      final page = _page(response);
      page.validateRequest(
        query: _query(_map(window['query'])),
        cursor: window['requested_cursor'] == null
            ? null
            : _map(window['requested_cursor']),
        limit: window['limit'] as int,
      );
      expect(page.totalCount, response['total_count']);
      expect(page.totals, response['totals']);
      expect(page.ownTotals, response['own_totals']);
      expect(
        page.ownCollectionIds,
        (response['own_collection_ids'] as List).toSet(),
      );
      if (page.totalCount == 0) {
        empty++;
      } else {
        positive++;
      }
      for (final row in page.items) {
        expect(row.createdAt.isUtc, isTrue);
        expect(row.amountMinor, inInclusiveRange(1, maxExactJsonInteger));
        if (!row.isCurrentUserContribution) {
          expect(row.transactionId, isNull);
        }
      }
    }
    expect(positive, greaterThan(20));
    expect(empty, greaterThan(0));
  });

  test(
    'actual SQL tie pagination appends complete exact totals without loss',
    () {
      final groups = <String, List<Map<String, dynamic>>>{};
      for (final window in windows) {
        groups.putIfAbsent(jsonEncode(window['query']), () => []).add(window);
      }
      final sorts = <String>{};
      var maxAggregate = false;
      var pagedChains = 0;
      for (final chain in groups.values) {
        final query = _query(_map(chain.first['query']));
        MemberHistoryPage? combined;
        for (final window in chain) {
          final next = _page(_map(window['response']));
          if (combined == null) {
            expect(window['requested_cursor'], isNull);
            combined = next;
          } else {
            expect(window['requested_cursor'], combined.nextCursor);
            combined = combined.append(next, query: query);
          }
        }
        expect(combined!.items.length, combined.totalCount);
        expect(combined.nextCursor, isNull);
        expect(
          combined.items.map((row) => row.id).toSet().length,
          combined.items.length,
        );
        var total = 0;
        var own = 0;
        for (final row in combined.items) {
          expect(
            row.amountMinor,
            lessThanOrEqualTo(maxExactJsonInteger - total),
          );
          total += row.amountMinor;
          if (row.isCurrentUserContribution) own += row.amountMinor;
        }
        expect(total, combined.totals['RWF'] ?? 0);
        expect(own, combined.ownTotals['RWF'] ?? 0);
        if (query.collectionId == null && query.search.isEmpty) {
          expect(combined.totalCount, 67);
          expect(total, maxExactJsonInteger);
          sorts.add(query.sort);
          maxAggregate = true;
        }
        if (chain.length > 1) pagedChains++;
      }
      expect(sorts, {'newest', 'oldest', 'highest', 'lowest'});
      expect(maxAggregate, isTrue);
      expect(pagedChains, greaterThanOrEqualTo(8));
    },
  );

  test(
    'actual SQL balances preserve nonzero totals, zero and unknown supporters',
    () {
      var unknown = 0;
      var zero = 0;
      var positive = 0;
      for (final wire in balances) {
        final summary = CollectionSummary.fromJson(wire);
        expect(summary.supporterCount, wire['supporter_count']);
        if (wire['supporter_count'] == null) {
          unknown++;
          expect(summary.supporterCountLabel, '—');
        }
        if ((wire['balances'] as List).isEmpty ||
            (wire['balances'] as List).every(
              (row) => _map(row)['amount_raised_minor'] == 0,
            )) {
          zero++;
          expect(summary.amountRaisedMinor, 0);
          expect(summary.currentUserBalanceMinor, 0);
        } else {
          positive++;
          final amount = _map((wire['balances'] as List).single);
          expect(summary.amountRaisedMinor, amount['amount_raised_minor']);
          expect(
            summary.currentUserBalanceMinor,
            amount['current_user_balance_minor'],
          );
        }
      }
      expect(unknown, greaterThan(0));
      expect(zero, greaterThan(0));
      expect(positive, greaterThan(0));
    },
  );

  test(
    'actual SQL exact maximum payment remains unchanged across JSON decoding',
    () {
      final page = windows
          .map((window) => _page(_map(window['response'])))
          .firstWhere(
            (page) =>
                page.items.length == 1 &&
                page.items.single.amountMinor == maxExactJsonInteger,
          );
      expect(page.totalCount, 1);
      expect(page.items.single.amountMinor.toString(), '9007199254740991');
      expect(page.totals['RWF'], maxExactJsonInteger);
      expect(page.ownTotals['RWF'], maxExactJsonInteger);
      expect(page.items.single.isCurrentUserContribution, isTrue);
    },
  );

  test(
    'actual SQL unsafe precision observations fail closed in client decoders',
    () {
      for (final observation in fixture['precision_observations'] as List) {
        final wire = _map(observation)['actual_response'];
        if (wire != null) {
          expect(() => _page(_map(wire)), throwsFormatException);
        }
      }
      final aggregate = _map(
        fixture['aggregate_observation'],
      )['actual_response'];
      if (aggregate != null) {
        expect(() => _page(_map(aggregate)), throwsFormatException);
      }
      // Empty observations mean the genuine server rejected each unsafe probe;
      // the gate retains exact SQL denial results rather than fabricating rows.
      expect(fixture['synthetic_mechanics_only'], isTrue);
    },
  );

  if (fixture.containsKey('concurrent_sorts')) {
    test(
      'actual committed SQL cursors remain fenced and append exact fresh windows in every sort',
      () {
        final observations = _map(fixture['concurrent_sorts']);
        expect(observations.keys.toSet(), {
          'newest',
          'oldest',
          'highest',
          'lowest',
        });
        for (final entry in observations.entries) {
          final wire = _map(entry.value);
          final old = _page(_map(wire['first']));
          final uncommitted = _page(_map(wire['uncommitted_next_page']));
          final query = MemberHistoryQuery(
            collectionId: old.items.single.collectionId,
            sort: entry.key,
          );
          old.validateRequest(query: query, cursor: null, limit: 1);
          uncommitted.validateRequest(
            query: query,
            cursor: old.nextCursor,
            limit: 1,
          );
          expect(old.append(uncommitted, query: query).items.length, 2);
          expect(_map(wire['stale_cursor_denial'])['sqlstate'], 'P0001');
          expect(
            _map(wire['stale_cursor_denial'])['reason'],
            'History changed',
          );
          final fresh = (wire['fresh_windows'] as List)
              .map((value) => _page(_map(value)))
              .toList();
          expect(fresh.length, 3);
          expect(
            () => old.append(fresh.first, query: query),
            throwsFormatException,
          );
          MemberHistoryPage? combined;
          for (final page in fresh) {
            page.validateRequest(
              query: query,
              cursor: combined?.nextCursor,
              limit: 1,
            );
            combined = combined == null
                ? page
                : combined.append(page, query: query);
          }
          expect(
            combined!.items.map((item) => item.id).toList(),
            wire['exact_committed_id_order'],
          );
          expect(combined.totalCount, 3);
          expect(combined.totals, {'RWF': 169});
          expect(combined.ownTotals, {'RWF': 162});
          expect(combined.nextCursor, isNull);
        }
      },
    );
  }
}
