import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_runtime_assets.dart';
import 'package:collect_app/core/supabase/realtime_invalidation.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _revision = '11111111111111111111111111111111';
MemberHistoryPage _page(
  List<int> indexes, {
  bool more = true,
  int count = 60,
  String revision = _revision,
}) => MemberHistoryPage(
  items: [
    for (final i in indexes)
      Contribution(
        id: i == 59 ? 'bank:$i' : 'momo:$i',
        collectionId: i == 59 ? 'older-group' : 'col-church',
        amountRwf: i == 59 ? 125 : 1000,
        currency: i == 59 ? 'EUR' : 'RWF',
        supporterLabel: 'Collect ID ${400000 + i}',
        isCurrentUserContribution: true,
        createdAt: DateTime.utc(2026, 9, 2).subtract(Duration(minutes: i)),
      ),
  ],
  totalCount: count,
  totals: count == 1 ? const {'EUR': 125} : const {'RWF': 59000, 'EUR': 125},
  ownTotals: count == 1 ? const {'EUR': 125} : const {'RWF': 59000, 'EUR': 125},
  ownCollectionIds: count == 1
      ? const {'older-group'}
      : const {'col-church', 'older-group'},
  revision: revision,
  nextCursor: more
      ? {'revision': revision, 'after': 'momo:${indexes.last}'}
      : null,
);

class _PagedRepository extends CollectRepository {
  _PagedRepository() : super.fixture() {
    final first = _page(List.generate(50, (i) => i));
    state = state.copyWith(
      contributions: first.items,
      historyPage: first,
      pendingIntentCount: 100,
    );
  }
  int calls = 0;
  bool fail = false;
  Completer<MemberHistoryPage>? pending;
  final queries = <MemberHistoryQuery>[];
  @override
  bool get isLive => true;
  @override
  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    calls++;
    queries.add(query);
    if (fail) throw StateError('Synthetic network failure');
    if (pending != null) return pending!.future;
    if (query.search.isNotEmpty) return _page([59], more: false, count: 1);
    if (cursor != null) {
      return _page(List.generate(10, (i) => i + 50), more: false);
    }
    return _page(List.generate(50, (i) => i));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  test('Home metrics and pending count use complete server aggregates', () {
    final repo = _PagedRepository();
    final container = ProviderContainer(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
    );
    addTearDown(container.dispose);
    expect(repo.state.contributions.length, 50);
    expect(container.read(raisedTotalsByCurrencyProvider), {
      'RWF': 59000,
      'EUR': 125,
    });
    expect(container.read(contributedCollectionIdsProvider), {
      'col-church',
      'older-group',
    });
    expect(container.read(pendingPaymentCountProvider), 100);
  });

  test(
    'load more coalesces concurrent taps and preserves complete aggregates',
    () async {
      final repo = _PagedRepository();
      final feed = MemberHistoryController(repo, const MemberHistoryQuery());
      addTearDown(feed.dispose);
      addTearDown(repo.dispose);
      repo.pending = Completer<MemberHistoryPage>();
      final request = feed.loadMore();
      await feed.loadMore();
      expect(repo.calls, 1);
      repo.pending!.complete(
        _page(List.generate(10, (i) => i + 50), more: false),
      );
      await request;
      expect(feed.state.page!.items.length, 60);
      expect(feed.state.page!.totals, {'RWF': 59000, 'EUR': 125});
      expect(feed.state.page!.nextCursor, isNull);
    },
  );

  test(
    'failed page keeps rows and cursor; retry succeeds without duplication',
    () async {
      final repo = _PagedRepository()..fail = true;
      final feed = MemberHistoryController(repo, const MemberHistoryQuery());
      addTearDown(feed.dispose);
      addTearDown(repo.dispose);
      await feed.loadMore();
      expect(feed.state.page!.items.length, 50);
      expect(feed.state.error, contains('Try again'));
      repo.fail = false;
      await feed.loadMore();
      expect(feed.state.page!.items.map((r) => r.id).toSet().length, 60);
      expect(feed.state.error, isNull);
    },
  );

  test('changed revision never appends to the old snapshot', () async {
    final repo = _PagedRepository()..pending = Completer<MemberHistoryPage>();
    final feed = MemberHistoryController(repo, const MemberHistoryQuery());
    addTearDown(feed.dispose);
    addTearDown(repo.dispose);
    final request = feed.loadMore();
    repo.pending!.complete(
      _page([50], revision: '22222222222222222222222222222222'),
    );
    await request;
    expect(feed.state.page!.items.length, 50);
    expect(feed.state.error, 'History changed. Refresh to continue.');
  });

  test(
    'disposed search/old account controller cannot publish late results',
    () async {
      final repo = _PagedRepository()..pending = Completer<MemberHistoryPage>();
      final feed = MemberHistoryController(repo, const MemberHistoryQuery());
      addTearDown(repo.dispose);
      final request = feed.loadMore();
      feed.dispose();
      repo.pending!.complete(_page([50], more: false));
      await request;
    },
  );

  test('revision, cursor, duplicates and aggregate schema fail closed', () {
    final first = _page([0]);
    expect(() => first.append(_page([0], more: false)), throwsFormatException);
    expect(
      () => MemberHistoryPage.fromJson({
        ...first.metadata,
        'total_count': -1,
      }, first.items),
      throwsFormatException,
    );
    expect(
      () => MemberHistoryPage.fromJson({
        ...first.metadata,
        'totals': {'RWF': -1},
      }, first.items),
      throwsFormatException,
    );
    expect(
      () => MemberHistoryPage.fromJson({
        ...first.metadata,
        'totals': {'USD': 1},
      }, first.items),
      throwsFormatException,
    );
    expect(
      () => MemberHistoryPage.fromJson({
        ...first.metadata,
        'next_cursor': {'revision': _revision, 'after': 'different'},
      }, first.items),
      throwsFormatException,
    );
  });

  test(
    'paged offline snapshot retains full totals and old cache cannot read it',
    () async {
      final page = _page(List.generate(50, (i) => i));
      const cache = CollectOfflineCache();
      await cache.save(
        CollectOfflineSnapshot(
          savedAt: DateTime.utc(2026, 9, 2),
          currentProfile: null,
          collections: const [],
          paymentIntents: const [],
          contributions: page.items,
          historyPage: page,
          pendingIntentCount: 100,
        ),
      );
      final restored = (await cache.read())!;
      expect(restored.contributions.length, 50);
      expect(restored.historyPage!.totalCount, 60);
      expect(restored.historyPage!.ownTotals, {'RWF': 59000, 'EUR': 125});
      expect(restored.pendingIntentCount, 100);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('collect.offline_snapshot.v3'), isFalse);
      expect(prefs.containsKey('collect.offline_snapshot.v4'), isTrue);
    },
  );

  test('sign-out clear wins over an already queued snapshot write', () async {
    const cache = CollectOfflineCache();
    final write = cache.save(
      CollectOfflineSnapshot(
        savedAt: DateTime.utc(2026, 9, 2),
        currentProfile: null,
        collections: const [],
        paymentIntents: const [],
        contributions: _page([0]).items,
      ),
    );
    final clear = cache.clear();
    await Future.wait([write, clear]);
    expect(await cache.read(), isNull);
  });

  test('MoMo and bank invalidations both refresh mobile financial state', () {
    expect(
      collectMobileRealtimeAreas,
      containsAll([
        'payments',
        'payment_intents',
        'ledger',
        'bank_intents',
        'bank_transactions',
        'bank_reconciliation',
      ]),
    );
  });

  testWidgets(
    'Activity loads older rows on demand and searches beyond its first page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _PagedRepository();
      final router = createAppRouter(initialLocation: '/activity');
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appRouterProvider.overrideWithValue(router),
            collectRepositoryProvider.overrideWith((ref) => repo),
          ],
          child: RepaintBoundary(key: captureKey, child: const CollectApp()),
        ),
      );
      await tester.pumpAndSettle();
      final appContext = tester.element(find.byType(MaterialApp).first);
      await tester.runAsync(
        () => precacheImage(
          const AssetImage(CollectRuntimeAssets.officialLogo),
          appContext,
        ),
      );
      await tester.pump();
      expect(find.textContaining('59,000'), findsWidgets);
      await tester.runAsync(
        () => _capture(captureKey, '43-paged-history-first-390.png'),
      );
      expect(
        repo.calls,
        0,
        reason: 'first page is already available from bootstrap',
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      for (var i = 0; i < 4; i++) {
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(find.text('Load more'), findsOneWidget);
      await tester.runAsync(
        () => _capture(captureKey, '44-paged-history-footer-390.png'),
      );
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(repo.calls, 1);
      for (var i = 0; i < 4; i++) {
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('400059'), findsWidgets);
      await tester.runAsync(
        () => _capture(captureKey, '45-paged-history-last-390.png'),
      );
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search activity'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '400059');
      await tester.pumpAndSettle();
      expect(repo.queries.last.search, '400059');
      expect(find.textContaining('400059'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    },
  );

  test(
    'late bootstrap response is ignored after authentication changes',
    () async {
      final response = Completer<http.Response>();
      var profileRequested = false;
      final client = SupabaseClient(
        'http://127.0.0.1:1',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('get_current_member_profile')) {
            profileRequested = true;
            return response.future;
          }
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'synthetic-access',
          'refresh_token': 'synthetic-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': '10000000-0000-0000-0000-000000000001',
            'aud': 'authenticated',
            'app_metadata': {},
            'user_metadata': {},
            'created_at': '2026-09-02T00:00:00Z',
          },
        }),
      );
      final repo = CollectRepository(supabase: client);
      addTearDown(repo.dispose);
      final load = repo.loadInitial();
      await Future<void>.delayed(Duration.zero);
      expect(profileRequested, isTrue);
      await repo.signOut();
      response.complete(
        http.Response(
          jsonEncode({
            'id': '10000000-0000-0000-0000-000000000001',
            'public_id': '123456',
            'whatsapp_phone': '250788123456',
            'country_code': 'RW',
            'currency_code': 'RWF',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await load;
      expect(repo.state.currentProfile, isNull);
      expect(repo.state.contributions, isEmpty);
      expect(repo.state.lastError, isNull);
      expect(await const CollectOfflineCache().read(), isNull);
    },
  );
}

Future<void> _capture(GlobalKey key, String filename) async {
  final directory = Platform.environment['COLLECT_PAGINATION_CAPTURES'];
  if (directory == null) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final screenshot = await boundary.toImage(pixelRatio: 1);
  final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
  await File('$directory/$filename').writeAsBytes(bytes!.buffer.asUint8List());
  screenshot.dispose();
}
