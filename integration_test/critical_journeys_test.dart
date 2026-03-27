import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/core/services/hive_runtime.dart';
import 'package:cool_app/features/momo/screens/momo_screen.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';

import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:cool_app/features/partners/rayon/screens/tickets_screen.dart';

import '../test/integration_smoke/test_harness.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeHiveRuntime();
  });

  group('Critical journeys', () {
    testWidgets('signed-out deep links land on onboarding', (tester) async {
      await pumpRouterApp(
        tester,
        initialLocation: '/momo?amount=5000',
        session: null,
        user: null,
      );

      // Should land on onboarding when not authenticated
      expect(find.text('Welcome to COOL'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('signed-in deep links land on target screen', (tester) async {
      await pumpRouterApp(
        tester,
        initialLocation: '/momo',
        session: fakeSession(),
        user: fakeUser(),
      );

      // Should navigate directly to MoMo when authenticated
      expect(find.byType(MomoScreen), findsOneWidget);
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
        ],
      );

      // Wait for async providers to resolve
      await settleTestApp(tester);
      await tester.pumpAndSettle();

      expect(find.text('Tickets'), findsOneWidget);
      expect(find.text('APR FC'), findsOneWidget);
    });

    testWidgets('dynamic home screen renders mocked admin banners and matches', (
      tester,
    ) async {
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
        imageUrl: 'mock.jpg',
        title: 'Ikibuga cyacu',
        subtitle: 'Dushyigikire ikipe yacu',
        isActive: true,
        sortOrder: 1,
        ctaLabel: 'Learn More',
        route: '/',
      );

      when(() => repository.loadData(userId: any(named: 'userId'))).thenAnswer(
        (_) async => RayonSportsData(
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
        ),
      );
      when(() => repository.getMatches(any(), any())).thenAnswer((_) async => [match]);
      when(() => repository.getFanMembership(any(), any())).thenAnswer((_) async => null);
      when(() => repository.getMembershipPackages(partnerId: any(named: 'partnerId'))).thenAnswer((_) async => []);

      await pumpRouterApp(
        tester,
        initialLocation: '/home',
        session: fakeSession(),
        user: fakeUser(),
        overrides: <Override>[
          rayonSportsRepositoryProvider.overrideWithValue(repository),
        ],
      );

      // Verify the dynamic content rendered directly on the home screen
      expect(find.text('Police FC'), findsOneWidget);
      expect(find.text('Ikibuga cyacu'), findsOneWidget);
      
      // Verify basic Bottom Nav structure is intact
      expect(find.text('Tickets'), findsWidgets); // Nav and Match ticket button
    });
  });
}
