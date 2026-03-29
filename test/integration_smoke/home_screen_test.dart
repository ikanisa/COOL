import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/providers/home_dashboard_provider.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/rayon/models/rs_models.dart';
import 'package:cool_app/features/home/screens/home_screen.dart';

import 'test_harness.dart';

FanMembership _sampleMembership() {
  return FanMembership(
    id: 'membership-1',
    userId: 'user-1',
    partnerId: 'partner-1',
    displayName: 'Alex Fan',
    tier: FanTier.gold,
    points: 2200,
    chapter: 'Kigali Central',
    membershipNumber: 'RS-2026-AAA111',
    joinedAt: DateTime(2026, 1, 1),
  );
}

RsMatch _sampleMatch() {
  return RsMatch(
    id: 'match-1',
    homeTeam: 'Rayon Sports',
    awayTeam: 'APR FC',
    competition: 'RPL',
    venue: 'Amahoro',
    matchDate: DateTime(2026, 4, 1),
    kickoffTime: '18:00',
    isOnSale: true,
    ticketGeneralPrice: 3000,
    ticketVipPrice: 6000,
    saleStartsAt: DateTime(2026, 3, 20),
    capacity: 1000,
  );
}

RayonSportsData _sampleRayonData() {
  final membership = _sampleMembership();
  final match = _sampleMatch();

  return RayonSportsData(
    partnerId: 'partner-1',
    membership: membership,
    joinedClubIds: const {'club-1'},
    registryMembers: [
      RsRegistryMember(
        userId: 'user-1',
        displayName: 'Alex Fan',
        membershipNumber: 'RS-2026-AAA111',
        points: 2200,
        tier: FanTier.gold,
        chapter: 'Kigali Central',
        joinedAt: DateTime(2026, 1, 1),
      ),
    ],
    achievements: const <RsAchievement>[],
    clubs: const [
      RsFanClub(
        id: 'club-1',
        partnerId: 'partner-1',
        name: 'Kigali Blue',
        region: 'Kigali',
        description: 'Main chapter',
        memberCount: 120,
        eventCount: 5,
        rating: 4.8,
        bannerEmoji: '🥁',
      ),
    ],
    products: const [
      RsProduct(
        id: 'product-1',
        partnerId: 'partner-1',
        name: 'Replica Jersey',
        category: ProductCategory.kits,
        price: 5000,
        imageEmoji: '👕',
        bgColor: Colors.blue,
        stock: 10,
        isActive: true,
        isNew: false,
      ),
    ],
    initiatives: const [
      RsInitiative(
        id: 'initiative-1',
        partnerId: 'partner-1',
        title: 'Youth Academy',
        description: 'Back the academy pipeline.',
        category: InitiativeCategory.youth,
        targetAmount: 1000000,
        raisedAmount: 125000,
        supporterCount: 42,
        isActive: true,
        endsAt: null,
      ),
    ],
    matches: [match],
    tickets: const <RsTicket>[],
  );
}

HomeDashboardData _sampleDashboardData() {
  return const HomeDashboardData(
    totalBalance: 12450,
    monthlyNetChange: 200,
    memberCount: 2,
  );
}

void main() {
  group('Home screen smoke', () {
    testWidgets('renders key home screen sections', (tester) async {
      final originalErrorWidgetBuilder = ErrorWidget.builder;
      try {
        await pumpScopedApp(
          tester,
          child: const HomeScreen(),
          session: fakeSession(),
          user: fakeUser(fullName: 'Alex Fan'),
          overrides: <Override>[
            rayonSportsDataProvider.overrideWith(
              (ref) => AsyncData(_sampleRayonData()),
            ),
            rayonMembershipProvider.overrideWith(
              (ref) => AsyncData(_sampleMembership()),
            ),
            rayonNextMatchProvider.overrideWith(
              (ref) => AsyncData(_sampleMatch()),
            ),
            rayonActionLoadingProvider.overrideWith((ref) => false),
            homeDashboardProvider.overrideWith((ref) => _sampleDashboardData()),
          ],
        );

        await settleTestApp(tester);

        // Hero card
        expect(find.textContaining('AMAHORO'), findsOneWidget);

        // Membership strip
        expect(find.text('CURRENT TIER'), findsOneWidget);
        expect(find.text('FAN POINTS'), findsOneWidget);

        // Fan Savings
        expect(find.textContaining('FAN SAVINGS'), findsOneWidget);

        // Quick Actions
        expect(find.text('QUICK ACTIONS'), findsOneWidget);
        expect(find.text('TICKETS'), findsOneWidget);
        expect(find.text('CONTRIBUTE'), findsOneWidget);
        expect(find.text('REWARDS'), findsOneWidget);
        expect(find.text('SCAN'), findsOneWidget);

        // Official Network
        expect(find.text('OFFICIAL NETWORK'), findsOneWidget);
        expect(find.text('CONNECTED'), findsOneWidget);

        // Global Fan Network
        expect(find.text('GLOBAL FAN NETWORK'), findsOneWidget);
        expect(find.text('FAN CLUBS'), findsOneWidget);

        // Fan Rewards
        expect(find.text('FAN REWARDS'), findsOneWidget);
        expect(find.text('POINTS'), findsOneWidget);

        // Club & Community
        expect(find.text('CLUB & COMMUNITY'), findsOneWidget);

        // Partner Network
        expect(find.text('PARTNER NETWORK'), findsOneWidget);
        expect(find.text('EXCLUSIVE\nBENEFITS.'), findsOneWidget);

        // Community Impact section
        expect(find.text('COMMUNITY IMPACT'), findsOneWidget);

        // Stadium Lighting
        expect(find.text('STADIUM\nLIGHTING'), findsOneWidget);
      } finally {
        ErrorWidget.builder = originalErrorWidgetBuilder;
      }
    });
  });
}
