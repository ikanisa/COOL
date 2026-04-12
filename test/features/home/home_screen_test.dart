import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/groups/models/group.dart';
import 'package:cool_app/features/groups/providers/groups_provider.dart';
import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/providers/home_dashboard_provider.dart';
import 'package:cool_app/features/home/screens/home_screen.dart';
import 'package:cool_app/features/home/widgets/home_sections.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:cool_app/shared/widgets/cool_icon_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('saving balance opens the user savings group', (tester) async {
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        groups: const <Group>[_communityGroup, _savingGroup],
      ),
    );
    await _pumpHomeFrame(tester);

    await tester.tap(find.byType(HomeSavingsHeroCard));
    await _pumpHomeFrame(tester);

    expect(find.text('Group saving-1'), findsOneWidget);
  });

  testWidgets(
    'saving balance opens groups when the user has no savings group',
    (tester) async {
      final router = _buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(router: router, groups: const <Group>[_communityGroup]),
      );
      await _pumpHomeFrame(tester);

      await tester.tap(find.byType(HomeSavingsHeroCard));
      await _pumpHomeFrame(tester);

      expect(find.text('Groups'), findsOneWidget);
    },
  );

  testWidgets('home communities show public groups even without membership', (
    tester,
  ) async {
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        groups: const <Group>[],
        publicGroups: const <Group>[_publicGroup],
      ),
    );
    await _pumpHomeFrame(tester);

    expect(find.text('Kigali Market Circle'), findsOneWidget);
    expect(find.text('No communities yet'), findsNothing);
  });

  testWidgets(
    'home communities section stays hidden when there are no groups',
    (tester) async {
      final router = _buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(
        _buildApp(
          router: router,
          groups: const <Group>[],
          publicGroups: const <Group>[],
        ),
      );
      await _pumpHomeFrame(tester);

      expect(find.text('Communities'), findsNothing);
      expect(find.text('No communities yet'), findsNothing);
      expect(find.text('View All'), findsNothing);
    },
  );

  testWidgets('home operations section stays hidden when there is no data', (
    tester,
  ) async {
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        groups: const <Group>[_communityGroup, _savingGroup],
      ),
    );
    await _pumpHomeFrame(tester);

    expect(find.text('Operations'), findsNothing);
    expect(find.text('No operations yet'), findsNothing);
  });

  testWidgets('home operations section appears when there are transactions', (
    tester,
  ) async {
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        groups: const <Group>[_communityGroup, _savingGroup],
        dashboard: _dashboardWithOperations,
      ),
    );
    await _pumpHomeFrame(tester);

    await tester.scrollUntilVisible(
      find.text('Savings contribution'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await _pumpHomeFrame(tester);

    expect(find.text('Operations'), findsOneWidget);
    expect(find.text('Savings contribution'), findsOneWidget);
  });

  testWidgets('home quick actions render as one inline icon row', (
    tester,
  ) async {
    final router = _buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _buildApp(
        router: router,
        groups: const <Group>[_communityGroup, _savingGroup],
      ),
    );
    await _pumpHomeFrame(tester);

    final iconBoxes = tester.widgetList<CoolIconBox>(find.byType(CoolIconBox));
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('SCAN'), findsOneWidget);
    expect(find.text('BioPay'), findsOneWidget);
    expect(find.text('NFC'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(iconBoxes.length, greaterThanOrEqualTo(4));
  });
}

Future<void> _pumpHomeFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Widget _buildApp({
  required GoRouter router,
  required List<Group> groups,
  List<Group>? publicGroups,
  HomeDashboardData dashboard = _dashboard,
}) {
  return ProviderScope(
    overrides: <Override>[
      currentUserProvider.overrideWith((ref) => _user),
      homeDashboardProvider.overrideWith((ref) async => dashboard),
      myGroupsProvider.overrideWith((ref) async => groups),
      publicGroupsProvider.overrideWith((ref) async => publicGroups ?? groups),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    ),
  );
}

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.groups,
        builder: (context, state) => const _MarkerScreen('Groups'),
      ),
      GoRoute(
        path: AppRoutes.groupDetail,
        builder: (context, state) =>
            _MarkerScreen('Group ${state.pathParameters['id']}'),
      ),
    ],
  );
}

class _MarkerScreen extends StatelessWidget {
  const _MarkerScreen(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
}

const _dashboard = HomeDashboardData(
  totalBalance: 120000,
  monthlyNetChange: 12000,
);

final _dashboardWithOperations = HomeDashboardData(
  totalBalance: 120000,
  monthlyNetChange: 12000,
  recentTransactions: <HomeDashboardTransaction>[
    HomeDashboardTransaction(
      title: 'Savings contribution',
      type: 'deposit',
      amount: 15000,
      currency: 'RWF',
      recordedAt: DateTime(2025, 1, 1, 10, 30),
      groupName: 'Savings Circle',
    ),
  ],
);

const _user = UserProfile(
  id: 'user-1',
  phone: '0788000000',
  fullName: 'Test User',
  momoNumber: '',
  momoProvider: '',
  country: 'RW',
);

const _communityGroup = Group(
  id: 'community-1',
  creatorId: 'user-1',
  name: 'Community Circle',
  type: 'community',
  visibility: 'public',
  amount: 50000,
  targetAmount: 100000,
  country: 'RW',
);

const _publicGroup = Group(
  id: 'public-1',
  creatorId: 'user-2',
  name: 'Kigali Market Circle',
  type: 'saving',
  visibility: 'public',
  amount: 300000,
  targetAmount: 0,
  country: 'RW',
  memberCount: 8,
  monthlyContribution: 15000,
);

const _savingGroup = Group(
  id: 'saving-1',
  creatorId: 'user-1',
  name: 'Savings Circle',
  type: 'saving',
  visibility: 'private',
  amount: 120000,
  targetAmount: 300000,
  country: 'RW',
);
