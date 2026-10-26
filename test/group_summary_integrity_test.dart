import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/features/collections/collections_screen.dart';
import 'package:collect_app/features/collections/collection_detail_screen.dart';
import 'package:collect_app/features/payments/contribute_entry_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/collect_repository_fixture.dart';

// Synthetic, in-memory widget fixtures. No server, payment or real identity.
CollectCollection _group() => CollectCollection(
  id: 'summary-fixture-group',
  slug: 'summary-fixture-group',
  creatorUserId: 'synthetic-owner',
  title: 'Summary fixture',
  description: 'Isolated summary-availability fixture',
  collectionType: CollectionType.ikimina,
  receiverMomoNumber: '0700000001',
  receiverDisplayLabel: 'Test receiver',
  receiverNetwork: 'mtn_momo',
  isPublic: true,
  createdAt: DateTime.utc(2026, 1, 1),
);

const _zero = CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
const _positive = CollectionSummary(
  amountRaisedRwf: 125000,
  supporterCount: 12,
);

Future<void> _pumpList(
  WidgetTester tester, {
  required bool lazy,
  CollectionSummary? summary,
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final group = _group();
  final summaries = summary == null
      ? <String, CollectionSummary>{}
      : <String, CollectionSummary>{group.id: summary};
  final list = lazy
      ? CustomScrollView(
          slivers: [
            GroupListSliver(collections: [group], summaries: summaries),
          ],
        )
      : SingleChildScrollView(
          child: GroupListPanel(collections: [group], summaries: summaries),
        );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(body: list),
    ),
  );
  await tester.pumpAndSettle();
}

String _groupAnnouncement(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        (widget.properties.label?.startsWith('Summary fixture,') ?? false),
  );
  expect(finder, findsOneWidget);
  return tester.widget<Semantics>(finder).properties.label!;
}

Future<void> _pumpSelection(
  WidgetTester tester, {
  required Map<String, CollectionSummary> authoritative,
  required Map<String, CollectionSummary> derived,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collectRepositoryProvider.overrideWith(
          (_) => CollectRepository.fixture(
            initialState: CollectState(
              currentProfile: null,
              collections: [_group()],
              paymentIntents: const [],
              contributions: const [],
              collectionSummaries: authoritative,
            ),
          ),
        ),
        // A caller must not mistake a derived/partial sum for a server aggregate.
        collectionSummariesProvider.overrideWithValue(derived),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: ContributeEntryScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a recent contribution page never becomes a complete summary', () {
    final fixture = FixtureCollectRepository();
    final state = fixture.state.copyWith(collectionSummaries: const {});
    final repo = CollectRepository.fixture(initialState: state);
    expect(repo.contributionsFor('qa-private-group'), isNotEmpty);
    expect(repo.summaryFor('qa-private-group'), isNull);
    repo.dispose();
    fixture.dispose();
  });

  testWidgets('group detail labels an absent aggregate unavailable', (
    tester,
  ) async {
    final fixture = FixtureCollectRepository();
    final state = fixture.state.copyWith(collectionSummaries: const {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectRepositoryProvider.overrideWith(
            (_) => CollectRepository.fixture(initialState: state),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: CollectionDetailScreen(collectionId: 'qa-private-group'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not available'), findsWidgets);
    expect(find.text('RWF 0'), findsNothing);
    expect(find.text('RWF 35,000'), findsNothing);
    expect(tester.takeException(), isNull);
    fixture.dispose();
  });

  testWidgets('groups discovery keeps an absent aggregate unknown', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectRepositoryProvider.overrideWith(
            (_) => FixtureCollectRepository(
              fixtureNow: DateTime.utc(2026, 7, 24, 21),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const CollectionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RWF 35,000'), findsOneWidget);
    expect(find.text('RWF 0'), findsNothing);
    expect(find.text('—'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final lazy in [false, true]) {
    final label = lazy ? 'lazy' : 'eager';
    testWidgets('$label: absent summary never becomes zero', (tester) async {
      await _pumpList(tester, lazy: lazy);
      expect(find.text('Not available'), findsOneWidget);
      expect(
        find.text(formatCurrencyTotals(_zero.totalsByCurrency)),
        findsNothing,
      );
      expect(_groupAnnouncement(tester), contains('Group total unavailable'));
      expect(
        _groupAnnouncement(tester),
        contains('Contributor count unavailable'),
      );
      expect(_groupAnnouncement(tester), isNot(contains('0 contributors')));
      expect(tester.takeException(), isNull);
    });
    testWidgets('$label: measured zero remains a measured zero', (
      tester,
    ) async {
      await _pumpList(tester, lazy: lazy, summary: _zero);
      expect(find.text('Not available'), findsNothing);
      expect(
        find.text(formatCurrencyTotals(_zero.totalsByCurrency)),
        findsOneWidget,
      );
      expect(_groupAnnouncement(tester), contains('0 contributors'));
      expect(tester.takeException(), isNull);
    });
    testWidgets('$label: loaded positive total and count are unchanged', (
      tester,
    ) async {
      await _pumpList(tester, lazy: lazy, summary: _positive);
      expect(
        find.text(formatCurrencyTotals(_positive.totalsByCurrency)),
        findsOneWidget,
      );
      expect(_groupAnnouncement(tester), contains('12 contributors'));
      expect(find.text('Not available'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$label: unknown count does not erase a known amount', (
      tester,
    ) async {
      const partial = CollectionSummary(
        amountRaisedRwf: 125000,
        supporterCount: null,
      );
      await _pumpList(tester, lazy: lazy, summary: partial);
      expect(
        find.text(formatCurrencyTotals(partial.totalsByCurrency)),
        findsOneWidget,
      );
      expect(
        _groupAnnouncement(tester),
        contains('Contributor count unavailable'),
      );
      expect(find.text('Not available'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('$label: unavailable copy is usable at 2x text', (
      tester,
    ) async {
      await _pumpList(tester, lazy: lazy, scale: 2);
      final text = tester.widget<Text>(find.text('Not available'));
      expect(text.softWrap, isTrue);
      expect(
        find.ancestor(
          of: find.text('Not available'),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
    testWidgets('$label: a removed aggregate does not retain the old total', (
      tester,
    ) async {
      await _pumpList(tester, lazy: lazy, summary: _positive);
      await _pumpList(tester, lazy: lazy);
      expect(find.text('Not available'), findsOneWidget);
      expect(
        find.text(formatCurrencyTotals(_positive.totalsByCurrency)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('selection does not display a synthesized aggregate', (
    tester,
  ) async {
    await _pumpSelection(
      tester,
      authoritative: const {},
      derived: {_group().id: _positive},
    );
    expect(find.text('Not available'), findsOneWidget);
    expect(
      find.text(formatCurrencyTotals(_positive.totalsByCurrency)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selection uses the loaded aggregate even if derived data differs',
    (tester) async {
      await _pumpSelection(
        tester,
        authoritative: {_group().id: _zero},
        derived: {_group().id: _positive},
      );
      expect(
        find.text(formatCurrencyTotals(_zero.totalsByCurrency)),
        findsOneWidget,
      );
      expect(
        find.text(formatCurrencyTotals(_positive.totalsByCurrency)),
        findsNothing,
      );
      expect(find.text('Not available'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
