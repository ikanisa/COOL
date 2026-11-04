import 'dart:async';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

const _revision = '0123456789abcdef0123456789abcdef';
const _profile = CollectProfile(
  id: 'history-owner-a',
  publicId: '900001',
  whatsappPhone: '+250700000001',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'mtn_momo',
  momoNumber: '0700000001',
);
const _other = CollectProfile(
  id: 'history-owner-b',
  publicId: '900002',
  whatsappPhone: '+250700000002',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'mtn_momo',
  momoNumber: '0700000002',
);

Contribution _row(int index, {int amount = 10}) => Contribution(
  id: 'history-$index',
  collectionId: 'group',
  amountRwf: amount,
  supporterLabel: 'Collect member',
  createdAt: DateTime.utc(2026, 9, 1).subtract(Duration(minutes: index)),
);
MemberHistoryPage _page(List<int> ids, {bool more = false, int total = 20}) =>
    MemberHistoryPage.fromJson(
      {
        'total_count': 2,
        'totals': {'RWF': total},
        'own_totals': {'RWF': 0},
        'own_collection_ids': <String>[],
        'revision': _revision,
        'next_cursor': more
            ? {'revision': _revision, 'after': _row(ids.last).id}
            : null,
      },
      [for (final id in ids) _row(id, amount: id == 0 ? total - 10 : 10)],
    );

class _Repository extends CollectRepository {
  _Repository({bool withPage = true})
    : super.fixture(
        initialState: CollectState(
          currentProfile: _profile,
          collections: const [],
          paymentIntents: const [],
          contributions: const [],
          historyPage: withPage ? _page([0], more: true) : null,
        ),
      );
  final requests = <Map<String, dynamic>?>[];
  Future<MemberHistoryPage> Function(Map<String, dynamic>? cursor)? onFetch;
  @override
  bool get isLive => true;
  void setOwner(CollectProfile owner) =>
      state = state.copyWith(currentProfile: owner);
  @override
  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    requests.add(cursor == null ? null : Map<String, dynamic>.from(cursor));
    return await (onFetch?.call(cursor) ?? Future.value(_page([0, 1])));
  }
}

// Expose the protected state only from a test subclass; do not change production
// visibility or suppress analyzer checks in the implementation.
class _Controller extends MemberHistoryController {
  _Controller(super.repository, super.query);
  MemberHistoryState get value => state;
}

void main() {
  test('append valid next page once and stop at complete history', () async {
    final repo = _Repository()..onFetch = (_) async => _page([1]);
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    await controller.loadMore();
    expect(controller.value.page!.items.length, 2);
    expect(controller.value.page!.nextCursor, isNull);
    await controller.loadMore();
    expect(repo.requests.length, 1);
  });
  test('concurrent load-more taps share the existing request', () async {
    final pending = Completer<MemberHistoryPage>();
    final repo = _Repository()..onFetch = (_) => pending.future;
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    final first = controller.loadMore();
    await controller.loadMore();
    expect(repo.requests.length, 1);
    pending.complete(_page([1]));
    await first;
    expect(controller.value.page!.items.length, 2);
  });
  test('refresh supersedes an in-flight continuation', () async {
    final old = Completer<MemberHistoryPage>();
    final fresh = Completer<MemberHistoryPage>();
    final repo = _Repository()
      ..onFetch = (cursor) => cursor == null ? fresh.future : old.future;
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    final more = controller.loadMore();
    final refresh = controller.refresh();
    fresh.complete(_page([0, 1], total: 25));
    await refresh;
    old.complete(_page([1]));
    await more;
    expect(controller.value.page!.totals['RWF'], 25);
    expect(controller.value.error, isNull);
  });
  test('duplicate refresh taps do not create concurrent refreshes', () async {
    final pending = Completer<MemberHistoryPage>();
    final repo = _Repository()..onFetch = (_) => pending.future;
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    final first = controller.refresh();
    await controller.refresh();
    expect(repo.requests.length, 1);
    pending.complete(_page([0, 1]));
    await first;
    expect(controller.value.loading, isFalse);
  });
  test(
    'changed aggregates clear old page and require refresh before more',
    () async {
      final repo = _Repository()..onFetch = (_) async => _page([1], total: 21);
      final controller = _Controller(repo, const MemberHistoryQuery());
      addTearDown(controller.dispose);
      addTearDown(repo.dispose);
      await controller.loadMore();
      expect(controller.value.page, isNull);
      expect(controller.value.error, 'History changed. Refresh to continue.');
      await controller.loadMore();
      expect(repo.requests.length, 1);
      repo.onFetch = (_) async => _page([0, 1]);
      await controller.refresh();
      expect(controller.value.page!.items.length, 2);
      expect(controller.value.error, isNull);
    },
  );
  test('server revision-change error requires refresh', () async {
    final repo = _Repository()
      ..onFetch = (_) async => throw const CollectApiException(
        message: 'Synthetic changed response',
        code: 'P0001',
      );
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    await controller.loadMore();
    await controller.loadMore();
    expect(repo.requests.length, 1);
    expect(controller.value.page, isNull);
    expect(controller.value.error, 'History changed. Refresh to continue.');
  });
  for (final entry in const {
    'scope': CollectApiException(
      code: 'history_scope_unavailable',
      httpStatusCode: 403,
    ),
    'session': CollectApiException(code: 'session_changed'),
    'invalid token': CollectApiException(code: 'invalid_token'),
    'auth exception': CollectAuthException('synthetic', statusCode: '401'),
    'unauthenticated': CollectApiException(httpStatusCode: 401),
    'forbidden': CollectApiException(httpStatusCode: 403),
  }.entries) {
    test(
      'access denial clears the old page and fences continuation: ${entry.key}',
      () async {
        final repo = _Repository()..onFetch = (_) async => throw entry.value;
        final controller = _Controller(repo, const MemberHistoryQuery());
        addTearDown(controller.dispose);
        addTearDown(repo.dispose);
        await controller.loadMore();
        expect(controller.value.page, isNull);
        expect(
          controller.value.error,
          'History access changed. Refresh to continue.',
        );
        await controller.loadMore();
        expect(repo.requests.length, 1);
        repo.onFetch = (_) async => _page([0, 1]);
        await controller.refresh();
        expect(controller.value.page!.items.length, 2);
        expect(controller.value.error, isNull);
      },
    );
  }
  test('late denial clears a newer refreshed page until revalidated', () async {
    final old = Completer<MemberHistoryPage>();
    final fresh = Completer<MemberHistoryPage>();
    final repo = _Repository()
      ..onFetch = (cursor) => cursor == null ? fresh.future : old.future;
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    final more = controller.loadMore();
    final refresh = controller.refresh();
    fresh.complete(_page([0, 1], total: 25));
    await refresh;
    old.completeError(const CollectApiException(httpStatusCode: 403));
    await more;
    expect(controller.value.page, isNull);
    expect(
      controller.value.error,
      'History access changed. Refresh to continue.',
    );
    repo.onFetch = (_) async => _page([0, 1], total: 25);
    await controller.refresh();
    expect(controller.value.page!.totals['RWF'], 25);
    expect(controller.value.error, isNull);
  });
  test('late revision change invalidates a newer refreshed page', () async {
    final old = Completer<MemberHistoryPage>();
    final fresh = Completer<MemberHistoryPage>();
    final repo = _Repository()
      ..onFetch = (cursor) => cursor == null ? fresh.future : old.future;
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    final more = controller.loadMore();
    final refresh = controller.refresh();
    fresh.complete(_page([0, 1], total: 25));
    await refresh;
    old.completeError(const CollectApiException(code: 'history_changed'));
    await more;
    expect(controller.value.page, isNull);
    expect(controller.value.error, 'History changed. Refresh to continue.');
  });
  test('late denial fences an already running refresh response', () async {
    final old = Completer<MemberHistoryPage>();
    final fresh = Completer<MemberHistoryPage>();
    final repo = _Repository()
      ..onFetch = (cursor) => cursor == null ? fresh.future : old.future;
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    final more = controller.loadMore();
    final refresh = controller.refresh();
    old.completeError(const CollectApiException(httpStatusCode: 403));
    await more;
    fresh.complete(_page([0, 1], total: 25));
    await refresh;
    expect(controller.value.page, isNull);
    repo.onFetch = (_) async => _page([0, 1], total: 25);
    await controller.refresh();
    expect(controller.value.page!.totals['RWF'], 25);
  });
  test(
    'late transient failure does not clear a newer refreshed page',
    () async {
      final old = Completer<MemberHistoryPage>();
      final fresh = Completer<MemberHistoryPage>();
      final repo = _Repository()
        ..onFetch = (cursor) => cursor == null ? fresh.future : old.future;
      final controller = _Controller(repo, const MemberHistoryQuery());
      addTearDown(controller.dispose);
      addTearDown(repo.dispose);
      final more = controller.loadMore();
      final refresh = controller.refresh();
      fresh.complete(_page([0, 1], total: 25));
      await refresh;
      old.completeError(StateError('synthetic network failure'));
      await more;
      expect(controller.value.page!.totals['RWF'], 25);
      expect(controller.value.error, isNull);
    },
  );
  test(
    'recreated default feed does not reuse a denied repository page',
    () async {
      final repo = _Repository()
        ..onFetch = (_) async =>
            throw const CollectApiException(httpStatusCode: 403);
      final previous = _Controller(repo, const MemberHistoryQuery());
      await previous.loadMore();
      expect(previous.value.page, isNull);
      previous.dispose();

      final fresh = Completer<MemberHistoryPage>();
      repo.onFetch = (_) => fresh.future;
      final reopened = _Controller(repo, const MemberHistoryQuery());
      addTearDown(reopened.dispose);
      addTearDown(repo.dispose);
      expect(reopened.value.page, isNull);
      expect(reopened.value.loading, isTrue);
      expect(repo.requests.length, 2);
      fresh.complete(_page([0, 1], total: 25));
      await Future<void>.delayed(Duration.zero);
      expect(reopened.value.page!.totals['RWF'], 25);
    },
  );
  test('denied refresh prevents reuse of the repository page', () async {
    final repo = _Repository()
      ..onFetch = (_) async =>
          throw const CollectApiException(httpStatusCode: 403);
    final previous = _Controller(repo, const MemberHistoryQuery());
    await previous.refresh();
    expect(previous.value.page, isNull);
    previous.dispose();

    final fresh = Completer<MemberHistoryPage>();
    repo.onFetch = (_) => fresh.future;
    final reopened = _Controller(repo, const MemberHistoryQuery());
    addTearDown(reopened.dispose);
    addTearDown(repo.dispose);
    expect(reopened.value.page, isNull);
    expect(reopened.value.loading, isTrue);
    fresh.complete(_page([0, 1]));
    await Future<void>.delayed(Duration.zero);
    expect(reopened.value.page!.items.length, 2);
  });
  test('scope denial clears other mounted history controllers', () async {
    final repo = _Repository()
      ..onFetch = (_) async =>
          throw const CollectApiException(httpStatusCode: 403);
    final first = _Controller(repo, const MemberHistoryQuery());
    final second = _Controller(repo, const MemberHistoryQuery());
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(repo.dispose);
    await first.loadMore();
    expect(first.value.page, isNull);
    expect(second.value.page, isNull);
    await second.loadMore();
    expect(repo.requests.length, 1);
    repo.onFetch = (_) async => _page([0, 1]);
    await second.refresh();
    expect(second.value.page!.items.length, 2);
  });
  test('disposed request can still invalidate a mounted sibling', () async {
    final pending = Completer<MemberHistoryPage>();
    final repo = _Repository()..onFetch = (_) => pending.future;
    final first = _Controller(repo, const MemberHistoryQuery());
    final second = _Controller(repo, const MemberHistoryQuery());
    addTearDown(second.dispose);
    addTearDown(repo.dispose);
    final request = first.loadMore();
    first.dispose();
    pending.completeError(const CollectApiException(httpStatusCode: 403));
    await request;
    expect(second.value.page, isNull);
  });
  test(
    'disposing a sibling during notification does not skip others',
    () async {
      final repo = _Repository()
        ..onFetch = (_) async =>
            throw const CollectApiException(httpStatusCode: 403);
      final first = _Controller(repo, const MemberHistoryQuery());
      final second = _Controller(repo, const MemberHistoryQuery());
      final third = _Controller(repo, const MemberHistoryQuery());
      final fourth = _Controller(repo, const MemberHistoryQuery());
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(fourth.dispose);
      addTearDown(repo.dispose);
      final remove = second.addListener((state) {
        if (state.page == null && third.mounted) third.dispose();
      });
      addTearDown(remove);
      await first.loadMore();
      expect(third.mounted, isFalse);
      expect(fourth.value.page, isNull);
    },
  );
  test('listener failure does not skip the remaining controllers', () async {
    final repo = _Repository()
      ..onFetch = (_) async =>
          throw const CollectApiException(httpStatusCode: 403);
    final first = _Controller(repo, const MemberHistoryQuery());
    final second = _Controller(repo, const MemberHistoryQuery());
    final third = _Controller(repo, const MemberHistoryQuery());
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(third.dispose);
    addTearDown(repo.dispose);
    Object? reported;
    second.onError = (error, _) => reported = error;
    final remove = second.addListener((state) {
      if (state.page == null) throw StateError('synthetic listener failure');
    });
    addTearDown(remove);
    await expectLater(first.loadMore(), throwsA(isA<Error>()));
    expect(reported, isA<StateError>());
    expect(third.value.page, isNull);
  });
  test('a loading observer failure leaves load more retryable', () async {
    final repo = _Repository()..onFetch = (_) async => _page([1]);
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    controller.onError = (_, _) {};
    final remove = controller.addListener((value) {
      if (value.loading) throw StateError('synthetic loading failure');
    });
    await expectLater(controller.loadMore(), throwsA(isA<Error>()));
    remove();
    expect(controller.value.loading, isFalse);
    expect(controller.value.page, isNotNull);
    expect(repo.requests, isEmpty);
    await controller.loadMore();
    expect(controller.value.page!.items.length, 2);
  });
  test('a loading observer failure releases the refresh guard', () async {
    final repo = _Repository()..onFetch = (_) async => _page([0, 1]);
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    controller.onError = (_, _) {};
    final remove = controller.addListener((value) {
      if (value.loading) throw StateError('synthetic loading failure');
    });
    await expectLater(controller.refresh(), throwsA(isA<Error>()));
    remove();
    expect(controller.value.loading, isFalse);
    expect(controller.value.page, isNotNull);
    expect(repo.requests, isEmpty);
    await controller.refresh();
    expect(repo.requests.length, 1);
    expect(controller.value.page!.items.length, 2);
  });
  for (final refresh in [false, true]) {
    test('loading observer account change does not restore old history '
        '(${refresh ? 'refresh' : 'load more'})', () async {
      final repo = _Repository();
      final controller = _Controller(repo, const MemberHistoryQuery());
      addTearDown(controller.dispose);
      addTearDown(repo.dispose);
      Object? reported;
      controller.onError = (error, _) => reported = error;
      final remove = controller.addListener((value) {
        if (value.loading) {
          repo.setOwner(_other);
          throw StateError('synthetic loading failure');
        }
      });
      await expectLater(
        refresh ? controller.refresh() : controller.loadMore(),
        throwsA(isA<Error>()),
      );
      remove();
      expect(reported, isA<StateError>());
      expect(controller.value.page, isNull);
      expect(controller.value.loading, isFalse);
      expect(repo.requests, isEmpty);
    });
  }
  test('source listener failure still invalidates a sibling', () async {
    final repo = _Repository()
      ..onFetch = (_) async =>
          throw const CollectApiException(httpStatusCode: 403);
    final first = _Controller(repo, const MemberHistoryQuery());
    final second = _Controller(repo, const MemberHistoryQuery());
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(repo.dispose);
    Object? reported;
    first.onError = (error, _) => reported = error;
    final remove = first.addListener((state) {
      if (state.page == null) {
        throw StateError('synthetic source listener failure');
      }
    });
    addTearDown(remove);
    await expectLater(first.loadMore(), throwsA(isA<Error>()));
    expect(reported, isA<StateError>());
    expect(second.value.page, isNull);
  });
  test(
    'source observer cannot seed the old page during invalidation',
    () async {
      final repo = _Repository()
        ..onFetch = (_) async =>
            throw const CollectApiException(httpStatusCode: 403);
      final source = _Controller(repo, const MemberHistoryQuery());
      final pending = Completer<MemberHistoryPage>();
      _Controller? added;
      addTearDown(source.dispose);
      addTearDown(repo.dispose);
      addTearDown(() {
        if (added?.mounted == true) added!.dispose();
      });
      final remove = source.addListener((state) {
        if (state.page == null && added == null) {
          repo.onFetch = (_) => pending.future;
          added = _Controller(repo, const MemberHistoryQuery());
        }
      });
      addTearDown(remove);
      await source.loadMore();
      expect(added, isNotNull);
      expect(added!.value.page, isNull);
      pending.complete(_page([0, 1]));
      await Future<void>.delayed(Duration.zero);
    },
  );
  test('old refresh completion cannot unlock a newer refresh', () async {
    final old = Completer<MemberHistoryPage>();
    final next = Completer<MemberHistoryPage>();
    final repo = _Repository()..onFetch = (_) => old.future;
    final source = _Controller(repo, const MemberHistoryQuery());
    final sibling = _Controller(repo, const MemberHistoryQuery());
    addTearDown(source.dispose);
    addTearDown(sibling.dispose);
    addTearDown(repo.dispose);
    final oldRefresh = sibling.refresh();
    repo.onFetch = (_) async =>
        throw const CollectApiException(httpStatusCode: 403);
    await source.loadMore();
    repo.onFetch = (_) => next.future;
    final nextRefresh = sibling.refresh();
    old.complete(_page([0, 1]));
    await oldRefresh;
    final duplicate = sibling.refresh();
    await Future<void>.delayed(Duration.zero);
    final requestsBeforeCompletion = repo.requests.length;
    next.complete(_page([0, 1], total: 25));
    await nextRefresh;
    await duplicate;
    expect(requestsBeforeCompletion, 3);
    expect(sibling.value.page!.totals['RWF'], 25);
  });
  test('transport failure keeps old page and allows a retry', () async {
    final repo = _Repository()
      ..onFetch = (_) async => throw StateError('private-server-detail');
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    await controller.loadMore();
    expect(controller.value.page!.items.length, 1);
    expect(controller.value.error, 'Could not load more. Try again.');
    repo.onFetch = (_) async => _page([1]);
    await controller.loadMore();
    expect(repo.requests.length, 2);
    expect(controller.value.page!.items.length, 2);
  });
  test(
    'failed refresh exposes safe copy and permits another refresh',
    () async {
      final repo = _Repository()
        ..onFetch = (_) async => throw StateError('secret');
      final controller = _Controller(repo, const MemberHistoryQuery());
      addTearDown(controller.dispose);
      addTearDown(repo.dispose);
      await controller.refresh();
      expect(controller.value.page, isNull);
      expect(controller.value.error, 'Connect to load the complete history.');
      repo.onFetch = (_) async => _page([0, 1]);
      await controller.refresh();
      expect(controller.value.error, isNull);
    },
  );
  test('live refresh cannot publish a truncated terminal page', () async {
    final repo = _Repository()..onFetch = (_) async => _page([0]);
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    await controller.refresh();
    expect(controller.value.page, isNull);
    expect(controller.value.error, isNotNull);
  });
  test('account change before a request clears former-owner records', () async {
    final repo = _Repository();
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    repo.setOwner(_other);
    await controller.loadMore();
    expect(repo.requests, isEmpty);
    expect(controller.value.page, isNull);
  });
  test(
    'account change while loading cannot publish former-owner history',
    () async {
      final pending = Completer<MemberHistoryPage>();
      final repo = _Repository()..onFetch = (_) => pending.future;
      final controller = _Controller(repo, const MemberHistoryQuery());
      addTearDown(controller.dispose);
      addTearDown(repo.dispose);
      final operation = controller.loadMore();
      repo.setOwner(_other);
      pending.complete(_page([1]));
      await operation;
      expect(controller.value.page, isNull);
      expect(controller.value.loading, isFalse);
    },
  );
  test(
    'disposed controller ignores completion and later callback invocations',
    () async {
      final pending = Completer<MemberHistoryPage>();
      final repo = _Repository()..onFetch = (_) => pending.future;
      final controller = _Controller(repo, const MemberHistoryQuery());
      addTearDown(repo.dispose);
      final operation = controller.loadMore();
      controller.dispose();
      pending.complete(_page([1]));
      await operation;
      await controller.refresh();
      await controller.loadMore();
      expect(repo.requests.length, 1);
    },
  );
  test('disposed repository invalidates a still-mounted controller', () async {
    final repo = _Repository();
    final controller = _Controller(repo, const MemberHistoryQuery());
    addTearDown(controller.dispose);
    repo.dispose();
    await controller.refresh();
    expect(controller.value.page, isNull);
    expect(repo.requests, isEmpty);
  });
  test(
    'repository replacement with an equal state tuple recreates provider',
    () async {
      final first = _Repository();
      final second = _Repository();
      final slot = StateProvider<_Repository>((_) => first);
      final container = ProviderContainer(
        overrides: [
          collectRepositoryProvider.overrideWith((ref) => ref.watch(slot)),
        ],
      );
      addTearDown(container.dispose);
      final provider = memberHistoryProvider(const MemberHistoryQuery());
      final subscription = container.listen(
        provider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final old = container.read(provider.notifier);
      container.read(slot.notifier).state = second;
      await container.pump();
      final current = container.read(provider.notifier);
      expect(identical(old, current), isFalse);
      expect(current.repository, same(second));
      expect(old.mounted, isFalse);
    },
  );
  test(
    'search debounce is cancelled on disposal before it invokes RPC',
    () async {
      final repo = _Repository(withPage: false);
      final controller = _Controller(
        repo,
        const MemberHistoryQuery(search: 'group'),
      );
      addTearDown(repo.dispose);
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(repo.requests, isEmpty);
    },
  );
}
