import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/models/member_history_page.dart';
import 'package:flutter_test/flutter_test.dart';

const _revision = '0123456789abcdef0123456789abcdef';
const _changed = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Contribution _row(int index, {int amount = 10, String group = 'group'}) =>
    Contribution(
      id: 'payment-${index.toString().padLeft(4, '0')}',
      collectionId: group,
      amountRwf: amount,
      supporterLabel: 'Collect member',
      createdAt: DateTime.utc(2026, 9, 1).subtract(Duration(minutes: index)),
    );

Map<String, dynamic> _metadata({
  int count = 3,
  String revision = _revision,
  String? after,
  Map<String, int>? totals,
  Map<String, int>? ownTotals,
  List<String> ownIds = const [],
}) => {
  'total_count': count,
  'totals': totals ?? (count == 0 ? <String, int>{} : {'RWF': 30}),
  'own_totals': ownTotals ?? (count == 0 ? <String, int>{} : {'RWF': 0}),
  'own_collection_ids': ownIds,
  'revision': revision,
  'next_cursor': after == null ? null : {'revision': revision, 'after': after},
};

MemberHistoryPage _page(
  List<Contribution> rows, {
  int count = 3,
  bool more = false,
  String revision = _revision,
  Map<String, int>? totals,
  Map<String, int>? ownTotals,
  List<String> ownIds = const [],
}) => MemberHistoryPage.fromJson(
  _metadata(
    count: count,
    revision: revision,
    after: more ? rows.last.id : null,
    totals: totals,
    ownTotals: ownTotals,
    ownIds: ownIds,
  ),
  rows,
);

void main() {
  group('page decoding', () {
    test('empty history and genuine zero totals remain valid', () {
      final page = _page([], count: 0);
      page.validateRequest(query: const MemberHistoryQuery());
      expect(page.items, isEmpty);
      expect(page.totalCount, 0);
    });
    test('nonempty page is immutable including the cursor', () {
      final rows = [_row(0)];
      final metadata = _metadata(after: rows.last.id);
      final page = MemberHistoryPage.fromJson(metadata, rows);
      rows.clear();
      (metadata['totals'] as Map)['RWF'] = 999;
      (metadata['next_cursor'] as Map)['after'] = 'changed';
      expect(page.items.single.id, _row(0).id);
      expect(page.totals['RWF'], 30);
      expect(page.nextCursor!['after'], _row(0).id);
      expect(page.nextCursor!.keys.toSet(), {'revision', 'after'});
      expect(() => page.nextCursor!['after'] = 'x', throwsUnsupportedError);
      expect(() => page.items.clear(), throwsUnsupportedError);
      expect(() => page.totals.clear(), throwsUnsupportedError);
      expect(() => page.ownCollectionIds.add('x'), throwsUnsupportedError);
    });
    for (final value in <Object?>[
      null,
      -1,
      1.5,
      '3',
      true,
      double.nan,
      double.infinity,
      9007199254740992,
    ]) {
      test('reject invalid or inexact count ${value.runtimeType}: $value', () {
        final metadata = _metadata()..['total_count'] = value;
        expect(
          () => MemberHistoryPage.fromJson(metadata, []),
          throwsFormatException,
        );
      });
    }
    for (final value in <Object?>[
      null,
      -1,
      1.5,
      '30',
      true,
      double.nan,
      double.infinity,
      9007199254740992,
    ]) {
      test(
        'reject invalid or inexact aggregate ${value.runtimeType}: $value',
        () {
          final metadata = _metadata()..['totals'] = {'RWF': value};
          expect(
            () => MemberHistoryPage.fromJson(metadata, [_row(0)]),
            throwsFormatException,
          );
        },
      );
    }
    test('accept common exact-integer maximum without coercion', () {
      final page = _page(
        [_row(0)],
        count: 9007199254740991,
        totals: {'RWF': 9007199254740991},
      );
      expect(page.totalCount, 9007199254740991);
    });
    test('nonempty history cannot substitute missing totals with zero', () {
      expect(() => _page([_row(0)], totals: {}), throwsFormatException);
    });
    test('nonempty history cannot declare a zero total', () {
      expect(() => _page([_row(0)], totals: {'RWF': 0}), throwsFormatException);
    });
    test('nonempty history must supply its own-total field', () {
      expect(() => _page([_row(0)], ownTotals: {}), throwsFormatException);
    });
    test('reject own aggregate greater than complete aggregate', () {
      expect(
        () => _page([_row(0)], ownTotals: {'RWF': 31}),
        throwsFormatException,
      );
    });
    test('reject duplicate payment IDs within one page', () {
      expect(() => _page([_row(0), _row(0)]), throwsFormatException);
    });
    test(
      'reject duplicate ownership IDs instead of silently deduplicating',
      () {
        expect(
          () => _page([_row(0)], ownIds: ['group', 'group']),
          throwsFormatException,
        );
      },
    );
    test('reject count smaller than delivered records', () {
      expect(() => _page([_row(0), _row(1)], count: 1), throwsFormatException);
    });
    test('reject cursor after complete result', () {
      expect(
        () => _page([_row(0)], count: 1, more: true),
        throwsFormatException,
      );
    });
    test('reject cursor pointing to another payment', () {
      final metadata = _metadata(after: 'different');
      expect(
        () => MemberHistoryPage.fromJson(metadata, [_row(0)]),
        throwsFormatException,
      );
    });
    test('reject empty history with positive aggregate', () {
      expect(
        () => _page([], count: 0, totals: {'RWF': 10}),
        throwsFormatException,
      );
    });
    test('reject invalid payment amounts', () {
      for (final amount in [0, -1, 9007199254740992]) {
        expect(() => _page([_row(0, amount: amount)]), throwsFormatException);
      }
    });
    test('reject untrimmed group IDs', () {
      expect(() => _page([_row(0, group: ' group')]), throwsFormatException);
    });
    test('reject cursor revision mismatch', () {
      final metadata = _metadata(after: _row(0).id);
      (metadata['next_cursor'] as Map)['revision'] = _changed;
      expect(
        () => MemberHistoryPage.fromJson(metadata, [_row(0)]),
        throwsFormatException,
      );
    });
    test('cursor error does not echo supplied metadata', () {
      final metadata = _metadata(after: 'secret-token-do-not-log');
      try {
        MemberHistoryPage.fromJson(metadata, [_row(0)]);
        fail('Expected a static error');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains('secret-token')));
      }
    });
  });

  group('request-bound wire windows', () {
    test('valid partial first page', () {
      _page([
        _row(0),
      ], more: true).validateRequest(query: const MemberHistoryQuery());
    });
    test('reject silent initial truncation', () {
      expect(
        () =>
            _page([_row(0)]).validateRequest(query: const MemberHistoryQuery()),
        throwsFormatException,
      );
    });
    test('reject empty page for nonempty history', () {
      expect(
        () => _page([]).validateRequest(query: const MemberHistoryQuery()),
        throwsFormatException,
      );
    });
    test('reject ignored selected-group filter', () {
      expect(
        () => _page([_row(0)], more: true).validateRequest(
          query: const MemberHistoryQuery(collectionId: 'other'),
        ),
        throwsFormatException,
      );
    });
    test('reject repeated anchor in continuation', () {
      expect(
        () => _page([_row(0)], more: true).validateRequest(
          query: const MemberHistoryQuery(),
          cursor: {'revision': _revision, 'after': _row(0).id},
        ),
        throwsFormatException,
      );
    });
    test('reject response to an old revision', () {
      expect(
        () => _page([_row(1)]).validateRequest(
          query: const MemberHistoryQuery(),
          cursor: {'revision': _changed, 'after': _row(0).id},
        ),
        throwsFormatException,
      );
    });
    test('reject a window larger than its requested limit', () {
      expect(
        () => _page(
          [_row(0), _row(1)],
          more: true,
        ).validateRequest(query: const MemberHistoryQuery(), limit: 1),
        throwsFormatException,
      );
    });
    test('reject unsupported sort', () {
      expect(
        () => _page(
          [_row(0)],
          more: true,
        ).validateRequest(query: const MemberHistoryQuery(sort: 'random')),
        throwsFormatException,
      );
    });
    for (final sort in ['newest', 'oldest', 'highest', 'lowest']) {
      test('accept and enforce $sort order', () {
        final first = _row(0, amount: 20);
        final last = _row(1, amount: 10);
        final ordered = (sort == 'oldest' || sort == 'lowest')
            ? [last, first]
            : [first, last];
        final query = MemberHistoryQuery(sort: sort);
        _page(ordered, count: 2).validateRequest(query: query);
        expect(
          () => _page(
            ordered.reversed.toList(),
            count: 2,
          ).validateRequest(query: query),
          throwsFormatException,
        );
      });
    }
    test('use payment ID ascending for tied timestamps and amounts', () {
      final a = _row(0);
      final b = Contribution(
        id: 'zzzz',
        collectionId: a.collectionId,
        amountRwf: a.amountRwf,
        supporterLabel: a.supporterLabel,
        createdAt: a.createdAt,
      );
      _page([
        a,
        b,
      ], count: 2).validateRequest(query: const MemberHistoryQuery());
      expect(
        () => _page([
          b,
          a,
        ], count: 2).validateRequest(query: const MemberHistoryQuery()),
        throwsFormatException,
      );
    });
  });

  group('continuation merging', () {
    test('complete a multi-page result exactly once', () {
      final first = _page([_row(0)], more: true);
      final second = first.append(
        _page([_row(1)], more: true),
        query: const MemberHistoryQuery(),
      );
      final complete = second.append(
        _page([_row(2)]),
        query: const MemberHistoryQuery(),
      );
      expect(complete.items.map((row) => row.id), [
        _row(0).id,
        _row(1).id,
        _row(2).id,
      ]);
      expect(complete.nextCursor, isNull);
      expect(first.items.length, 1);
      expect(second.items.length, 2);
    });
    test('reject an append after a terminal page', () {
      expect(
        () => _page([_row(0)], count: 1).append(_page([_row(1)], count: 1)),
        throwsFormatException,
      );
    });
    test(
      'reject duplicate across pages without modifying existing history',
      () {
        final first = _page([_row(0)], more: true);
        expect(
          () => first.append(_page([_row(0), _row(1)])),
          throwsFormatException,
        );
        expect(first.items.length, 1);
      },
    );
    test('reject changed aggregate despite identical revision and count', () {
      expect(
        () => _page([
          _row(0),
        ], more: true).append(_page([_row(1), _row(2)], totals: {'RWF': 999})),
        throwsFormatException,
      );
    });
    test('reject changed own aggregate', () {
      expect(
        () => _page(
          [_row(0)],
          more: true,
        ).append(_page([_row(1), _row(2)], ownTotals: {'RWF': 10})),
        throwsFormatException,
      );
    });
    test('reject changed ownership group IDs', () {
      expect(
        () => _page([
          _row(0),
        ], more: true).append(_page([_row(1), _row(2)], ownIds: ['group'])),
        throwsFormatException,
      );
    });
    test('compare ownership sets by value rather than order', () {
      final first = _page([_row(0)], more: true, ownIds: ['g1', 'g2']);
      final result = first.append(
        _page([_row(1), _row(2)], ownIds: ['g2', 'g1']),
      );
      expect(result.totalCount, 3);
    });
    test('reject changed revision or count', () {
      final first = _page([_row(0)], more: true);
      expect(
        () => first.append(_page([_row(1), _row(2)], revision: _changed)),
        throwsFormatException,
      );
      expect(
        () => first.append(_page([_row(1), _row(2)], count: 4)),
        throwsFormatException,
      );
    });
    test('reject prematurely terminal continuation', () {
      expect(
        () => _page([_row(0)], more: true).append(_page([_row(1)])),
        throwsFormatException,
      );
    });
    test('reject continuation after all advertised rows were received', () {
      expect(
        () => _page([
          _row(0),
        ], more: true).append(_page([_row(1), _row(2)], more: true)),
        throwsFormatException,
      );
    });
    test('reject out-of-order cross-page boundary', () {
      expect(
        () => _page(
          [_row(1)],
          more: true,
        ).append(_page([_row(0), _row(2)]), query: const MemberHistoryQuery()),
        throwsFormatException,
      );
    });
    test('reject more rows than the complete count', () {
      expect(
        () => _page([
          _row(0),
          _row(1),
        ], more: true).append(_page([_row(2), _row(3)])),
        throwsFormatException,
      );
    });
    test('immutable metadata survives a cache-style round trip', () {
      final first = _page([_row(0)], more: true);
      final restored = MemberHistoryPage.fromJson(first.metadata, first.items);
      expect(restored.nextCursor, first.nextCursor);
      expect(restored.totals, first.totals);
      expect(() => restored.nextCursor!.clear(), throwsUnsupportedError);
    });
  });
}
