import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/status/providers/home_status_providers.dart';
import 'package:cool_app/features/admin/models/special_product.dart';
import 'package:cool_app/features/admin/providers/special_products_provider.dart';
import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/models/nexus_recommendation.dart';
import 'package:cool_app/features/home/models/quick_action.dart';
import 'package:cool_app/features/home/providers/home_dashboard_provider.dart';
import 'package:cool_app/features/home/providers/nexus_provider.dart';
import 'package:cool_app/features/home/providers/quick_action_provider.dart';
import 'package:cool_app/features/home/screens/services_hub_screen.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/screens/rayon_home_screen.dart';

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

void main() {
  group('Home and services smoke', () {
    testWidgets('rayon home prioritizes club command surfaces', (tester) async {
      final originalErrorWidgetBuilder = ErrorWidget.builder;
      try {
        await pumpScopedApp(
          tester,
          child: const RayonHomeScreen(),
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
          ],
        );

        await settleTestApp(tester);

        expect(find.text('RAYON SPORTS COMMAND'), findsOneWidget);
        expect(find.text('Club Services'), findsOneWidget);
        expect(find.text('Chapter Standings'), findsOneWidget);
        expect(find.text('Open Profile'), findsOneWidget);
        expect(find.text('Buy Tickets'), findsWidgets);
        expect(find.text('Fan Clubs & Chapters'), findsNothing);
      } finally {
        ErrorWidget.builder = originalErrorWidgetBuilder;
      }
    });

    testWidgets(
      'services hub keeps momo, groups, and partners as secondary utilities',
      (tester) async {
        final originalErrorWidgetBuilder = ErrorWidget.builder;
        try {
          await pumpScopedApp(
            tester,
            child: const ServicesHubScreen(),
            session: fakeSession(),
            user: fakeUser(),
            overrides: <Override>[
              homeDashboardProvider.overrideWith(
                (ref) async => HomeDashboardData(
                  totalBalance: 120000,
                  monthlyNetChange: 15000,
                  memberCount: 3,
                  recentTransactions: <HomeDashboardTransaction>[
                    HomeDashboardTransaction(
                      title: 'Contribution',
                      type: 'credit',
                      amount: 5000,
                      currency: 'RWF',
                      recordedAt: DateTime(2026, 3, 12, 10),
                    ),
                  ],
                ),
              ),
              currentCountryQuickActionsProvider.overrideWith(
                (ref) async => const <QuickAction>[
                  QuickAction(
                    id: 'groups',
                    title: 'Groups',
                    subtitle: 'Savings and invites',
                    route: '/groups',
                  ),
                  QuickAction(
                    id: 'momo',
                    title: 'MoMo',
                    subtitle: 'Pay and statements',
                    route: '/momo',
                  ),
                  QuickAction(
                    id: 'partners',
                    title: 'Partners',
                    subtitle: 'Rayon and clubs',
                    route: '/partners',
                  ),
                ],
              ),
              bankPartnersProvider.overrideWith(
                (ref) async => const <Partner>[],
              ),
              activeSeasonProvider.overrideWith((ref) async => null),
              questsProvider.overrideWith((ref) => const []),
              activeSpecialProductsProvider.overrideWith(
                (ref) async => const <SpecialProduct>[],
              ),
              nexusRecommendationsProvider.overrideWith(
                (ref) async => const <NexusRecommendation>[],
              ),
            ],
          );

          await settleTestApp(tester);

          expect(find.text('Services'), findsOneWidget);
          expect(find.text('Utilities'), findsOneWidget);
          expect(find.text('Recent activity'), findsOneWidget);
          expect(find.text('Mobile Money'), findsOneWidget);
          expect(find.text('Groups'), findsOneWidget);
          expect(find.text('Mobility'), findsOneWidget);
          expect(find.text('Profile'), findsOneWidget);
        } finally {
          ErrorWidget.builder = originalErrorWidgetBuilder;
        }
      },
    );

    testWidgets(
      'services hub still shows empty activity states without promoting utilities over club surfaces',
      (tester) async {
        final originalErrorWidgetBuilder = ErrorWidget.builder;
        try {
          await pumpScopedApp(
            tester,
            child: const ServicesHubScreen(),
            session: fakeSession(),
            user: fakeUser(),
            overrides: <Override>[
              homeDashboardProvider.overrideWith(
                (ref) async => const HomeDashboardData(
                  totalBalance: 0,
                  monthlyNetChange: 0,
                  memberCount: 0,
                  recentTransactions: <HomeDashboardTransaction>[],
                ),
              ),
              currentCountryQuickActionsProvider.overrideWith(
                (ref) async => const <QuickAction>[
                  QuickAction(
                    id: 'groups',
                    title: 'Groups',
                    subtitle: 'Savings and invites',
                    route: '/groups',
                  ),
                ],
              ),
              bankPartnersProvider.overrideWith(
                (ref) async => const <Partner>[],
              ),
              activeSeasonProvider.overrideWith((ref) async => null),
              questsProvider.overrideWith((ref) => const []),
              activeSpecialProductsProvider.overrideWith(
                (ref) async => const <SpecialProduct>[],
              ),
              nexusRecommendationsProvider.overrideWith(
                (ref) async => const <NexusRecommendation>[],
              ),
            ],
          );

          await settleTestApp(tester);

          expect(find.text('No recent activity'), findsOneWidget);
          expect(find.text('Utilities'), findsOneWidget);
          expect(find.text('Groups'), findsWidgets);
        } finally {
          ErrorWidget.builder = originalErrorWidgetBuilder;
        }
      },
    );
  });
}
