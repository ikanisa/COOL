import 'dart:async';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';
import '../fixtures/collect_scroll_fixture.dart';

class _UnknownRepository extends FixtureCollectRepository {
  _UnknownRepository({bool own = false}) {
    state = state.copyWith(
      usingStaleCache: true,
      historyPage: null,
      pendingIntentCount: null,
      contributions: own
          ? [
              Contribution(
                id: 'partial-payment',
                collectionId: 'qa-private-group',
                amountRwf: 10,
                supporterLabel: 'You',
                isCurrentUserContribution: true,
                createdAt: DateTime.utc(2000),
              ),
            ]
          : const [],
    );
  }
}

class _AbsentHistory extends MemberHistoryController {
  _AbsentHistory(super.repository, super.query) {
    state = const MemberHistoryState();
  }

  @override
  Future<void> refresh() async {}
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  String route,
  CollectRepository repo, {
  bool absentHistory = false,
  String? historyGroup,
  Future<List<CollectMember>> Function()? roster,
}) async {
  final router = createAppRouter(initialLocation: route);
  final container = ProviderContainer(
    overrides: [
      collectBackendClientProvider.overrideWithValue(null),
      appRouterProvider.overrideWithValue(router),
      collectRepositoryProvider.overrideWith((_) => repo),
      if (absentHistory)
        memberHistoryProvider(
          MemberHistoryQuery(collectionId: historyGroup),
        ).overrideWith(
          (_) => _AbsentHistory(
            repo,
            MemberHistoryQuery(collectionId: historyGroup),
          ),
        ),
      if (roster != null)
        groupMembersProvider('qa-private-group').overrideWith((_) => roster()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const CollectApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'absent complete aggregates remain unknown despite partial owned rows',
    () {
      final repo = _UnknownRepository(own: true);
      final container = ProviderContainer(
        overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
      );
      addTearDown(container.dispose);
      expect(container.read(pendingPaymentCountProvider), isNull);
      expect(container.read(raisedTotalsByCurrencyProvider), isNull);
      expect(
        container.read(contributedCollectionIdsProvider),
        contains('qa-private-group'),
      );
    },
  );
  for (final own in [false, true]) {
    testWidgets(
      'supported-group filter marks ${own ? 'partial positive' : 'empty partial'} ownership as incomplete',
      (tester) async {
        await _pump(
          tester,
          '/groups?filter=contributed',
          _UnknownRepository(own: own),
        );
        expect(find.text('Supported groups unavailable'), findsOneWidget);
        expect(find.text('No groups yet'), findsNothing);
        expect(find.text('Refresh groups'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('absent group ledger page cannot claim no confirmed activity', (
    tester,
  ) async {
    await _pump(
      tester,
      '/groups/qa-private-group/ledger',
      _UnknownRepository(),
      absentHistory: true,
      historyGroup: 'qa-private-group',
    );
    expect(find.text('Could not load data'), findsOneWidget);
    expect(find.text('No ledger activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('absent group activity page cannot claim no contributions', (
    tester,
  ) async {
    await _pump(
      tester,
      '/groups/qa-private-group',
      _UnknownRepository(),
      absentHistory: true,
      historyGroup: 'qa-private-group',
    );
    await revealCollectPageContent(tester, find.text('Could not load data'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load data'), findsOneWidget);
    expect(find.text('No contributions yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'absent activity page cannot be shown as zero confirmed history',
    (tester) async {
      await _pump(
        tester,
        '/activity',
        _UnknownRepository(),
        absentHistory: true,
      );
      expect(find.text('Could not load data'), findsOneWidget);
      expect(find.text('No activity yet'), findsNothing);
      expect(find.text('RWF 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'refreshing retained roster removes previous IDs and amounts before reply',
    (tester) async {
      final pending = Completer<List<CollectMember>>();
      var count = 0;
      final container = await _pump(
        tester,
        '/groups/qa-private-group/members',
        FixtureCollectRepository(),
        roster: () async {
          if (++count > 1) return pending.future;
          return [
            CollectMember(
              publicId: '654321',
              role: 'member',
              status: 'active',
              joinedAt: DateTime.utc(2000),
              amountScope: 'shared',
              contributionTotals: const {'RWF': 1234},
            ),
          ];
        },
      );
      expect(find.text('654321'), findsOneWidget);
      expect(find.text('RWF 1,234'), findsOneWidget);
      container.invalidate(groupMembersProvider('qa-private-group'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('654321'), findsNothing);
      expect(find.text('RWF 1,234'), findsNothing);
      expect(find.text('Loading members'), findsOneWidget);
      pending.completeError(StateError('Synthetic access removed'));
      await tester.pumpAndSettle();
      expect(find.text('654321'), findsNothing);
      expect(find.text('Could not load members'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
