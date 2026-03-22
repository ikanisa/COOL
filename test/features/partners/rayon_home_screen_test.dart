import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/screens/rayon_home_screen.dart';

import '../../integration_smoke/test_harness.dart';

void main() {
  testWidgets('Rayon home renders command surfaces with redesign data', (
    tester,
  ) async {
    final membership = FanMembership(
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

    final match = RsMatch(
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

    const club = RsFanClub(
      id: 'club-1',
      partnerId: 'partner-1',
      name: 'Kigali Blue',
      region: 'Kigali',
      description: 'Main chapter',
      memberCount: 120,
      eventCount: 5,
      rating: 4.8,
      bannerEmoji: '🥁',
    );

    const product = RsProduct(
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
    );

    const initiative = RsInitiative(
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
    );

    final data = RayonSportsData(
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
      clubs: const [club],
      products: const [product],
      initiatives: const [initiative],
      matches: [match],
      tickets: const <RsTicket>[],
    );

    await pumpScopedApp(
      tester,
      child: const RayonHomeScreen(),
      session: fakeSession(),
      user: fakeUser(fullName: 'Alex Fan'),
      overrides: <Override>[
        rayonSportsDataProvider.overrideWith((ref) => AsyncData(data)),
        rayonMembershipProvider.overrideWith((ref) => AsyncData(membership)),
        rayonNextMatchProvider.overrideWith((ref) => AsyncData(match)),
        rayonActionLoadingProvider.overrideWith((ref) => false),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('RAYON SPORTS COMMAND'), findsOneWidget);
    expect(find.text('Club Services'), findsOneWidget);
    expect(find.text('Chapter Standings'), findsOneWidget);
    expect(find.text('Ticket Office'), findsOneWidget);
    expect(find.text('Open Profile'), findsOneWidget);
    expect(find.text('Buy Tickets'), findsWidgets);
  });
}
