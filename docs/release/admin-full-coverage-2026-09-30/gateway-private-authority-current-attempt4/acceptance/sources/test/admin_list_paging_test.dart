import 'dart:async';

import 'package:collect_app/admin/core/admin_list_paging.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

AdminListResult _window(int total, int limit, int offset) => AdminListResult(
  total: total,
  rows: [
    for (var i = offset; i < offset + limit && i < total; i++)
      AdminTableRowData(
        id: 'synthetic-$i',
        title: 'Synthetic row $i',
        subtitle: '',
        status: 'active',
        amount: '',
        extra: const {'country_code': 'RW'},
      ),
  ],
);

void main() {
  test('server page beyond 100 retains its exact range and total', () async {
    final calls = <(int, int)>[];
    final page = await loadAdminListPage(
      page: 4,
      fetch: (limit, offset) async {
        calls.add((limit, offset));
        return _window(125, limit, offset);
      },
    );
    expect(calls, [(25, 100)]);
    expect((page.page, page.start, page.end, page.total), (4, 101, 125, 125));
  });

  for (final (total, lastPage, start, end) in [
    (25, 0, 1, 25),
    (26, 1, 26, 26),
    (50, 1, 26, 50),
    (51, 2, 51, 51),
  ]) {
    test('25-row boundary at total $total has the exact last window', () async {
      final calls = <(int, int)>[];
      final loaded = await loadAdminListPage(
        page: lastPage,
        fetch: (limit, offset) async {
          calls.add((limit, offset));
          return _window(total, limit, offset);
        },
      );
      expect(calls, [(25, lastPage * 25)]);
      expect(
        (loaded.lastPage, loaded.start, loaded.end, loaded.total),
        (lastPage, start, end, total),
      );
    });
  }

  test(
    'a disappeared last page is fetched again at the valid offset',
    () async {
      final calls = <int>[];
      final page = await loadAdminListPage(
        page: 4,
        fetch: (limit, offset) async {
          calls.add(offset);
          return _window(53, limit, offset);
        },
      );
      expect(calls, [100, 50]);
      expect((page.page, page.start, page.end, page.total), (2, 51, 53, 53));
      expect(page.result.rows.first.id, 'synthetic-50');
    },
  );

  test('an empty queue is confirmed at page zero before reset', () async {
    var calls = 0;
    final page = await loadAdminListPage(
      page: 4,
      fetch: (limit, offset) async {
        calls++;
        return _window(0, limit, offset);
      },
    );
    expect(calls, 2);
    expect((page.page, page.start, page.end, page.total), (0, 0, 0, 0));
  });

  for (final (total, expectedOffsets, expectedPage) in [
    (25, [25, 0], 0),
    (53, [100, 0, 50], 2),
  ]) {
    test('zero total from an expired offset recovers $total rows', () async {
      final offsets = <int>[];
      final loaded = await loadAdminListPage(
        page: total == 25 ? 1 : 4,
        fetch: (limit, offset) async {
          offsets.add(offset);
          // Emulate an RPC whose count(*) window loses the total after a
          // deletion makes the requested offset invalid.
          if (offset >= total) {
            return const AdminListResult(rows: [], total: 0);
          }
          return _window(total, limit, offset);
        },
      );
      expect(offsets, expectedOffsets);
      expect(loaded.page, expectedPage);
      expect(loaded.total, total);
      expect(loaded.result.rows, isNotEmpty);
    });
  }

  test('a growing queue preserves the requested page', () async {
    final page = await loadAdminListPage(
      page: 1,
      fetch: (limit, offset) async => _window(151, limit, offset),
    );
    expect((page.page, page.start, page.end, page.lastPage), (1, 26, 50, 6));
  });

  test('recovery is bounded while the queue keeps shrinking', () async {
    final totals = [100, 75, 50];
    final calls = <int>[];
    await expectLater(
      loadAdminListPage(
        page: 4,
        fetch: (limit, offset) async {
          calls.add(offset);
          return _window(totals[calls.length - 1], limit, offset);
        },
      ),
      throwsStateError,
    );
    expect(calls, [100, 75, 50]);
  });

  test('zero recovery budget performs no recovery read', () async {
    var calls = 0;
    await expectLater(
      loadAdminListPage(
        page: 4,
        maxRecoveryAttempts: 0,
        fetch: (limit, offset) async {
          calls++;
          return _window(53, limit, offset);
        },
      ),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test('an obsolete request never starts a network read', () async {
    var calls = 0;
    await expectLater(
      loadAdminListPage(
        page: 0,
        isCurrent: () => false,
        fetch: (limit, offset) async {
          calls++;
          return _window(1, limit, offset);
        },
      ),
      throwsA(isA<AdminPageRequestSuperseded>()),
    );
    expect(calls, 0);
  });

  test('an obsolete response cannot trigger recovery or publication', () async {
    var current = true;
    var calls = 0;
    final deferred = Completer<AdminListResult>();
    final pending = loadAdminListPage(
      page: 4,
      isCurrent: () => current,
      fetch: (limit, offset) {
        calls++;
        return deferred.future;
      },
    );
    final rejected = expectLater(
      pending,
      throwsA(isA<AdminPageRequestSuperseded>()),
    );
    current = false;
    deferred.complete(_window(2, 25, 100));
    await rejected;
    expect(calls, 1);
  });

  test('transport errors propagate with no fallback request', () async {
    final error = StateError('synthetic transport error');
    var calls = 0;
    await expectLater(
      loadAdminListPage(
        page: 0,
        fetch: (limit, offset) async {
          calls++;
          throw error;
        },
      ),
      throwsA(same(error)),
    );
    expect(calls, 1);
  });

  test(
    'an in-range empty batch is an error rather than an empty queue',
    () async {
      await expectLater(
        loadAdminListPage(
          page: 0,
          fetch: (_, _) async => const AdminListResult(rows: [], total: 125),
        ),
        throwsFormatException,
      );
    },
  );

  for (final input in [(-1, 25, 2), (0, 0, 2), (0, 25, -1)]) {
    test('invalid page arguments $input fail before fetching', () async {
      var calls = 0;
      await expectLater(
        loadAdminListPage(
          page: input.$1,
          pageSize: input.$2,
          maxRecoveryAttempts: input.$3,
          fetch: (limit, offset) async {
            calls++;
            return _window(0, limit, offset);
          },
        ),
        throwsRangeError,
      );
      expect(calls, 0);
    });
  }
}
