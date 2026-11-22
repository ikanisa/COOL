import 'dart:async';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/ledger/ledger_screen.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/screen_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/collect_repository_fixture.dart';

class _LedgerRepository extends FixtureCollectRepository {
  _LedgerRepository() : super(fixtureNow: DateTime.utc(2026, 9, 2));

  final load = Completer<void>();
  final queries = <MemberHistoryQuery>[];

  @override
  bool get isLive => true;

  @override
  Future<void> loadInitial() => load.future;

  @override
  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    queries.add(query);
    return const MemberHistoryPage(
      items: [],
      totalCount: 0,
      totals: {},
      ownTotals: {},
      ownCollectionIds: {},
      revision: '11111111111111111111111111111111',
    );
  }

  void updateSyncTime() {
    state = state.copyWith(lastSuccessfulSyncAt: DateTime.utc(2026, 9, 3));
  }
}

Future<void> _settleSearch(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _pumpLedger(
  WidgetTester tester,
  ProviderContainer scope, {
  String? paymentId,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: LedgerScreen(
            collectionId: 'qa-private-group',
            initialPaymentId: paymentId,
          ),
        ),
      ),
    ),
  );
  await _settleSearch(tester);
}

Future<void> _refresh(WidgetTester tester) =>
    tester.widget<ScreenScaffold>(find.byType(ScreenScaffold)).onRefresh!();

void main() {
  testWidgets('a pending Ledger refresh keeps private search with its owner', (
    tester,
  ) async {
    final original = _LedgerRepository(), replacement = _LedgerRepository();
    final active = StateProvider<_LedgerRepository>((_) => original);
    final scope = ProviderContainer(
      overrides: [
        collectRepositoryProvider.overrideWith((ref) => ref.watch(active)),
      ],
    );
    addTearDown(scope.dispose);
    await _pumpLedger(tester, scope);
    final before = scope.read(memberGroupSessionProvider);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'original payment reference',
    );
    await _settleSearch(tester);
    expect(original.queries.last.search, 'original payment reference');
    final pending = _refresh(tester);

    scope.read(active.notifier).state = replacement;
    await _settleSearch(tester);
    final after = scope.read(memberGroupSessionProvider);
    expect(after.profileId, before.profileId);
    expect(after.generation, before.generation);
    expect(after.repository, same(replacement));
    expect(find.byType(TextField), findsNothing);
    expect(replacement.queries, isNotEmpty);
    final count = replacement.queries.length;
    original.load.complete();
    await pending;
    await _settleSearch(tester);
    expect(replacement.queries, hasLength(count));
    expect(
      replacement.queries.where((query) => query.search.isNotEmpty),
      isEmpty,
    );
  });

  testWidgets(
    'Ledger keeps the visible query through same-owner syncs and deep links',
    (tester) async {
      final repository = _LedgerRepository();
      final scope = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((_) => repository)],
      );
      addTearDown(scope.dispose);
      await _pumpLedger(tester, scope, paymentId: 'First-Payment');
      expect(repository.queries.last.search, 'first-payment');
      final pending = _refresh(tester);
      await tester.enterText(find.byType(TextField), 'updated search');
      await _settleSearch(tester);
      repository.updateSyncTime();
      await _settleSearch(tester);
      expect(find.text('updated search'), findsOneWidget);
      expect(repository.queries.last.search, 'updated search');
      final count = repository.queries.length;

      repository.load.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(repository.queries, hasLength(count));
      await _refresh(tester);
      expect(repository.queries.skip(count).map((query) => query.search), [
        'updated search',
      ]);
      await _pumpLedger(tester, scope, paymentId: 'Next-Payment');
      expect(find.text('Next-Payment'), findsOneWidget);
      expect(repository.queries.last.search, 'next-payment');
    },
  );
}
