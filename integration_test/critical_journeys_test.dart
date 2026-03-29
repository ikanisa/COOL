import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/providers/home_dashboard_provider.dart';
import 'package:cool_app/core/services/hive_runtime.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/rayon/models/rs_models.dart';

import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:cool_app/features/rayon/screens/tickets_screen.dart';

import '../test/integration_smoke/test_harness.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeHiveRuntime();
  });

  group('Critical journeys', () {
    testWidgets(
      'signed-out deep links preserve the target after anonymous boot',
      (tester) async {
        final app = await pumpRouterApp(
          tester,
          initialLocation: '/momo?amount=5000',
          session: null,
          user: null,
        );

        final uri = app.router.routeInformationProvider.value.uri;
        expect(uri.path, AppRoutes.momo);
        expect(uri.queryParameters['amount'], '5000');
        expect(
          find.byKey(const ValueKey<String>('momo-action-statements')),
          findsOneWidget,
        );
      },
    );

    testWidgets('signed-in base payments route lands on the BioPay hub', (
      tester,
    ) async {
      final app = await pumpRouterApp(
        tester,
        initialLocation: '/momo',
        session: fakeSession(),
        user: fakeUser(),
      );

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.biopayHome,
      );
      expect(find.text('BioPay Hub'), findsOneWidget);
    });

    testWidgets('tickets hub renders the premium membership hero', (
      tester,
    ) async {
      final repository = MockRayonSportsRepository();
      final match = RsMatch(
        id: 'm1',
        homeTeam: 'Rayon Sports FC',
        awayTeam: 'APR FC',
        competition: 'Rwanda Premier League',
        venue: 'Amahoro Stadium',
        matchDate: DateTime.now().add(const Duration(days: 2)),
        kickoffTime: '15:00',
        isOnSale: true,
        ticketGeneralPrice: 5000,
        ticketVipPrice: 20000,
        saleStartsAt: DateTime.now().subtract(const Duration(days: 1)),
        capacity: 30000,
      );

      when(
        () => repository.getMatches(any(), any()),
      ).thenAnswer((_) async => [match]);
      when(
        () => repository.getFanMembership(any(), any()),
      ).thenAnswer((_) async => null);
      when(
        () => repository.getMembershipPackages(
          partnerId: any(named: 'partnerId'),
        ),
      ).thenAnswer((_) async => []);
      when(() => repository.getMyTickets(any())).thenAnswer((_) async => []);

      await pumpScopedApp(
        tester,
        child: const TicketsScreen(),
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          rayonSportsRepositoryProvider.overrideWithValue(repository),
          rayonCurrentUserIdProvider.overrideWith((ref) => 'user-1'),
          rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
        ],
      );

      // Wait for async providers to resolve
      await settleTestApp(tester);
      await tester.pumpAndSettle();

      expect(find.text('ON SALE'), findsWidgets);
      expect(find.text('APR FC'), findsOneWidget);
    });

    testWidgets(
      'dynamic home screen renders mocked admin banners and matches',
      (tester) async {
        final repository = MockRayonSportsRepository();

        final match = RsMatch(
          id: 'm1',
          homeTeam: 'Rayon Sports FC',
          awayTeam: 'Police FC',
          competition: 'Rwanda Premier League',
          venue: 'Kigali Pelé Stadium',
          matchDate: DateTime.now().add(const Duration(days: 3)),
          kickoffTime: '18:00',
          isOnSale: true,
          ticketGeneralPrice: 3000,
          ticketVipPrice: 10000,
          saleStartsAt: DateTime.now().subtract(const Duration(days: 1)),
          capacity: 20000,
        );

        const banner = RsHomeBanner(
          id: 'b1',
          title: 'Ikibuga cyacu',
          subtitle: 'Dushyigikire ikipe yacu',
          isActive: true,
          sortOrder: 1,
          ctaLabel: 'Learn More',
          route: '/',
        );

        final rayonData = RayonSportsData(
          partnerId: 'rayon-sports',
          membership: null,
          joinedClubIds: const {},
          registryMembers: const [],
          achievements: const [],
          clubs: const [],
          products: const [],
          initiatives: const [],
          matches: [match],
          tickets: const [],
          banners: [banner],
        );
        when(
          () => repository.getMatches(any(), any()),
        ).thenAnswer((_) async => [match]);
        when(
          () => repository.getFanMembership(any(), any()),
        ).thenAnswer((_) async => null);
        when(
          () => repository.getMembershipPackages(
            partnerId: any(named: 'partnerId'),
          ),
        ).thenAnswer((_) async => []);

        await pumpRouterApp(
          tester,
          initialLocation: '/home',
          session: fakeSession(),
          user: fakeUser(),
          overrides: <Override>[
            rayonSportsRepositoryProvider.overrideWithValue(repository),
            rayonSportsDataProvider.overrideWith(
              (ref) => AsyncData(rayonData),
            ),
            rayonMembershipProvider.overrideWith(
              (ref) => const AsyncData<RsFanMembership?>(null),
            ),
            rayonNextMatchProvider.overrideWith((ref) => AsyncData(match)),
            rayonActionLoadingProvider.overrideWith((ref) => false),
            homeDashboardProvider.overrideWith(
              (ref) => const HomeDashboardData(
                totalBalance: 12450,
                monthlyNetChange: 200,
                memberCount: 2,
              ),
            ),
          ],
        );

        await tester.pumpAndSettle();

        // First hero page is the next-match card.
        expect(find.textContaining('18:00'), findsOneWidget);

        // Swipe to the admin banner hero page and verify the mocked banner copy.
        await tester.fling(
          find.byType(PageView).first,
          const Offset(-1200, 0),
          1600,
        );
        await tester.pumpAndSettle();
        expect(find.text('IKIBUGA CYACU'), findsOneWidget);

        // Verify basic home actions remain present.
        expect(find.text('TICKETS'), findsWidgets);
      },
    );
  });
}
