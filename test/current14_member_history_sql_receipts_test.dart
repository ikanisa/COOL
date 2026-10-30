@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/models/member_history_page.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Integration-only: real isolated PostgreSQL/domain receipts, never synthetic
// decoder packets or a substitute for hosted/device/financial acceptance.
const packetPath = String.fromEnvironment('CURRENT14_HISTORY_PACKET');
const packetSha = String.fromEnvironment('CURRENT14_HISTORY_PACKET_SHA256');
const inputsPath = String.fromEnvironment('CURRENT14_HISTORY_INPUTS');
const inputsSha = String.fromEnvironment('CURRENT14_HISTORY_INPUTS_SHA256');
const sqlPath = String.fromEnvironment('CURRENT14_HISTORY_SQL');
const sqlSha = String.fromEnvironment('CURRENT14_HISTORY_SQL_SHA256');
Map<String, dynamic> object(Object? value) =>
    Map<String, dynamic>.from(value! as Map);
MemberHistoryPage page(Map<String, dynamic> value) {
  final rows = value['items'];
  if (rows is! List || rows.length > 50 || rows.any((row) => row is! Map)) {
    throw const FormatException('Invalid financial page');
  }
  return MemberHistoryPage.fromJson(value, [
    for (final row in rows)
      if (value['contract_version'] == 2)
        Contribution.historyEventFromJson(object(row))
      else
        Contribution.fromJson(object(row)),
  ]);
}

MemberHistoryQuery query(Map<String, dynamic> value) => MemberHistoryQuery(
  collectionId: value['collection_id'] as String?,
  search: value['search'] as String,
  sort: value['sort'] as String,
);

void main() {
  late List<int> raw;
  late Map<String, dynamic> packet;
  late List<Map<String, dynamic>> windows;
  setUpAll(() {
    if ([
      packetPath,
      packetSha,
      inputsPath,
      inputsSha,
      sqlPath,
      sqlSha,
    ].any((value) => value.isEmpty)) {
      throw StateError(
        'Run the current14 SQL fixture and provide its source-bound define file.',
      );
    }
    raw = File(packetPath).readAsBytesSync();
    packet = object(jsonDecode(utf8.decode(raw)));
    windows = (packet['pages'] as List).map(object).toList();
  });
  test(
    'current14 native SQL packet has immutable runtime and statement provenance',
    () {
      expect(sha256.convert(raw).toString(), packetSha);
      expect(
        sha256.convert(File(inputsPath).readAsBytesSync()).toString(),
        inputsSha,
      );
      expect(
        sha256.convert(File(sqlPath).readAsBytesSync()).toString(),
        sqlSha,
      );
      expect(packet['source_inputs_sha256'], inputsSha);
      expect(
        packet['format'],
        'collect.current14.actual-member-history-sql.v1',
      );
      expect(object(packet['fixture'])['current14'], isTrue);
      expect(
        object(packet['fixture'])['normal_runtime_role'],
        'collect_runtime',
      );
      expect(
        object(packet['fixture'])['financial_posting_acceptance'],
        isFalse,
      );
      expect(packet['provider_calls'], 0);
      expect(packet['hosted_acceptance'], isFalse);
      final statements = jsonDecode(File(sqlPath).readAsStringSync()) as List;
      expect(statements.length, packet['SQL_statement_count']);
      expect(statements, isNotEmpty);
    },
  );

  test(
    'actual current14 v1 and v2 windows satisfy the shared decoder and requested scope',
    () {
      var positive = 0, empty = 0;
      final versions = <int>{};
      for (final window in windows) {
        final decoded = page(object(window['response']));
        decoded.validateRequest(
          query: query(object(window['query'])),
          cursor: window['requested_cursor'] == null
              ? null
              : object(window['requested_cursor']),
          limit: window['limit'] as int,
        );
        versions.add(window['contract_version'] as int);
        if (decoded.totalCount == 0) {
          empty++;
        } else {
          positive++;
        }
        for (final item in decoded.items) {
          expect(item.createdAt.isUtc, isTrue);
          expect(item.amountMinor, inInclusiveRange(1, 9007199254740991));
          if (!item.isCurrentUserContribution) {
            expect(item.transactionId, isNull);
          }
        }
      }
      expect(versions, {1, 2});
      expect(positive, greaterThan(20));
      expect(empty, greaterThan(0));
    },
  );

  test(
    'actual current14 tied pages append complete exact aggregates in all four sorts',
    () {
      final chains = <String, List<Map<String, dynamic>>>{};
      for (final window in windows) {
        if (object(window['response'])['total_count'] != 67) continue;
        final key = jsonEncode([window['contract_version'], window['query']]);
        chains.putIfAbsent(key, () => []).add(window);
      }
      final sorts = <int, Set<String>>{};
      for (final chain in chains.values) {
        final wanted = query(object(chain.first['query']));
        MemberHistoryPage? combined;
        for (final window in chain) {
          final next = page(object(window['response']));
          expect(window['requested_cursor'], combined?.nextCursor);
          combined = combined == null
              ? next
              : combined.append(next, query: wanted);
        }
        expect(combined!.items.length, 67);
        expect(combined.items.map((e) => e.id).toSet().length, 67);
        expect(combined.nextCursor, isNull);
        expect(
          combined.items.fold<int>(0, (sum, row) => sum + row.amountMinor),
          9007199254740991,
        );
        expect(combined.totals['RWF'], 9007199254740991);
        expect(
          combined.items
              .where((row) => row.isCurrentUserContribution)
              .fold<int>(0, (sum, row) => sum + row.amountMinor),
          combined.ownTotals['RWF'],
        );
        sorts
            .putIfAbsent(chain.first['contract_version'] as int, () => {})
            .add(wanted.sort);
      }
      expect(chains.length, greaterThanOrEqualTo(8));
      for (final version in [1, 2]) {
        expect(sorts[version], {'newest', 'oldest', 'highest', 'lowest'});
      }
    },
  );

  test(
    'actual current14 balances and maximum single payment preserve SQL integers',
    () {
      var zero = 0, positive = 0, maximum = 0;
      for (final raw in packet['balances'] as List) {
        final wire = object(raw),
            decoded = CollectionSummary.fromJson(object(raw));
        final amount = object((wire['balances'] as List).single);
        expect(decoded.supporterCount, wire['supporter_count']);
        expect(decoded.amountRaisedMinor, amount['amount_raised_minor']);
        expect(
          decoded.currentUserBalanceMinor,
          amount['current_user_balance_minor'],
        );
        if (decoded.amountRaisedMinor == 0) {
          zero++;
        } else {
          positive++;
        }
      }
      for (final window in windows) {
        final decoded = page(object(window['response']));
        if (decoded.totalCount == 1 &&
            decoded.items.single.amountMinor == 9007199254740991) {
          expect(decoded.totals['RWF'], 9007199254740991);
          expect(decoded.ownTotals['RWF'], 9007199254740991);
          maximum++;
        }
      }
      expect(zero, greaterThan(0));
      expect(positive, greaterThan(0));
      expect(maximum, 2);
    },
  );

  test(
    'actual current14 current-contract precision, tenant and revoked-session refusals remain refusals',
    () {
      final precision = (packet['precision_observations'] as List)
          .map(object)
          .toList();
      expect(precision.where((o) => o['sqlstate'] == '23514'), hasLength(1));
      final aggregateRefusals = precision
          .where((observation) => observation['response'] != null)
          .toList();
      expect(aggregateRefusals, hasLength(2));
      expect(
        aggregateRefusals
            .map((observation) => observation['contract_version'])
            .toSet(),
        {1, 2},
      );
      for (final observation in aggregateRefusals) {
        final response = object(observation['response']);
        expect(response['status'], 503);
        expect(object(response['body'])['code'], 'history_unavailable');
        expect(() => page(object(response['body'])), throwsFormatException);
      }
      expect(
        object(object(packet['foreign_response'])['body'])['total_count'],
        0,
      );
      expect(object(packet['revoked_response'])['status'], anyOf(401, 403));
    },
  );

  test(
    'actual committed and uncommitted current14 cursors preserve all four sort chains',
    () {
      final observations = object(packet['concurrent_sorts']);
      expect(observations.keys.toSet(), {
        'newest',
        'oldest',
        'highest',
        'lowest',
      });
      for (final entry in observations.entries) {
        final wire = object(entry.value),
            first = page(object(object(entry.value)['first']));
        final wanted = MemberHistoryQuery(
          collectionId: first.items.single.collectionId,
          sort: entry.key,
        );
        final uncommitted = page(object(wire['uncommitted_next_page']));
        first.validateRequest(query: wanted, cursor: null, limit: 1);
        uncommitted.validateRequest(
          query: wanted,
          cursor: first.nextCursor,
          limit: 1,
        );
        expect(first.append(uncommitted, query: wanted).items.length, 2);
        final denial = object(wire['actual_stale_cursor_response']);
        expect(denial['status'], 409);
        expect(object(denial['body'])['code'], 'history_changed');
        final fresh = (wire['fresh_windows'] as List)
            .map((x) => page(object(x)))
            .toList();
        expect(
          () => first.append(fresh.first, query: wanted),
          throwsFormatException,
        );
        MemberHistoryPage? combined;
        for (final next in fresh) {
          next.validateRequest(
            query: wanted,
            cursor: combined?.nextCursor,
            limit: 1,
          );
          combined = combined == null
              ? next
              : combined.append(next, query: wanted);
        }
        expect(combined!.items.length, combined.totalCount);
        expect(
          combined.items.map((x) => x.id).toSet().length,
          combined.totalCount,
        );
        expect(
          combined.items.fold<int>(0, (sum, row) => sum + row.amountMinor),
          combined.totals['RWF'],
        );
        expect(combined.nextCursor, isNull);
      }
    },
  );
}
