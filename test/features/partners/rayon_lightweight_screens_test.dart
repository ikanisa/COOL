import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/screens/support_detail_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/support_screen.dart';
import 'package:cool_app/features/partners/rayon/rayon_payment.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:cool_app/features/partners/screens/rayon/club_shop_screen.dart';
import 'package:cool_app/features/partners/screens/rayon/fan_clubs_screen.dart';
import 'package:cool_app/features/partners/screens/rayon/shop_checkout_screen.dart';
import 'package:cool_app/features/partners/screens/rayon/tickets_screen.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  late MockRayonSportsRepository repository;
  late RsFanMembership membership;
  late RsFanClub club;
  late RsProduct product;
  late RsMatch match;
  late RsTicket ticket;
  late RsInitiative initiative;
  late RsInitiativeContribution contribution;

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    List<Override> overrides = const <Override>[],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rayonSportsRepositoryProvider.overrideWithValue(repository),
          rayonCurrentUserIdProvider.overrideWith((ref) => 'user-1'),
          rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
          ...overrides,
        ],
        child: MaterialApp(home: screen),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  setUp(() {
    repository = MockRayonSportsRepository();
    membership = FanMembership(
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
    club = const RsFanClub(
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
    product = const RsProduct(
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
    match = RsMatch(
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
    ticket = RsTicket(
      id: 'ticket-1',
      matchId: 'match-1',
      match: match,
      userId: 'user-1',
      seatType: SeatType.general,
      amountPaid: 3000,
      qrCode: 'qr-1',
      momoReference: 'momo-1',
      status: TicketStatus.valid,
      purchasedAt: DateTime(2026, 3, 25),
    );
    initiative = const RsInitiative(
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
    contribution = RsInitiativeContribution(
      id: 'contribution-1',
      initiativeId: 'initiative-1',
      userId: 'user-2',
      amount: 5000,
      momoReference: 'momo-1',
      status: 'confirmed',
      createdAt: DateTime(2026, 3, 1, 14, 30),
      supporterName: 'Jamie Supporter',
    );

    when(
      () => repository.getUserClubs('user-1'),
    ).thenAnswer((_) async => <RsFanClub>[club]);
    when(
      () => repository.getFanClubs('partner-1', null),
    ).thenAnswer((_) async => <RsFanClub>[club]);
    when(
      () => repository.getProducts('partner-1', null),
    ).thenAnswer((_) async => <RsProduct>[product]);
    when(
      () => repository.getFanMembership('user-1', 'partner-1'),
    ).thenAnswer((_) async => membership);
    when(
      () => repository.getMatches('partner-1', false),
    ).thenAnswer((_) async => <RsMatch>[match]);
    when(
      () => repository.getMyTickets('user-1'),
    ).thenAnswer((_) async => <RsTicket>[ticket]);
    when(
      () => repository.getInitiatives('partner-1'),
    ).thenAnswer((_) async => <RsInitiative>[initiative]);
    when(
      () => repository.getRecentContributionActivity('initiative-1', 10),
    ).thenAnswer((_) async => <RsInitiativeContribution>[contribution]);
    when(() => repository.getActivePaymentRoute()).thenAnswer(
      (_) async => const PartnerPaymentRoute(
        id: 'route-1',
        partnerId: 'partner-1',
        partnerName: 'Rayon Sports',
        partnerSlug: 'rayon-sports',
        countryCode: 'RW',
        providerId: 'mtn_rwanda',
        recipientCode: '060000',
        reconciliationLabel: 'Rayon Sports',
        status: PartnerPaymentRouteStatus.active,
      ),
    );
  });

  testWidgets(
    'fan clubs screen builds from lightweight providers without aggregate loadData',
    (tester) async {
      await pumpScreen(tester, const FanClubsScreen());

      expect(find.text('Fan Clubs'), findsOneWidget);

      verify(() => repository.getFanClubs('partner-1', null)).called(1);
      verify(() => repository.getUserClubs('user-1')).called(1);
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );

  testWidgets(
    'club shop screen builds from lightweight providers without aggregate loadData',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await pumpScreen(tester, const ClubShopScreen());

      expect(find.text('Club Shop'), findsOneWidget);

      verify(() => repository.getProducts('partner-1', null)).called(1);
      verify(
        () => repository.getFanMembership('user-1', 'partner-1'),
      ).called(1);
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );

  testWidgets(
    'tickets screen builds from lightweight providers without aggregate loadData',
    (tester) async {
      await pumpScreen(tester, const TicketsScreen());

      expect(find.text('Tickets'), findsOneWidget);
      expect(find.text('Gold access active'), findsOneWidget);

      verify(() => repository.getMatches('partner-1', false)).called(1);
      verify(
        () => repository.getFanMembership('user-1', 'partner-1'),
      ).called(1);
      verify(() => repository.getMyTickets('user-1')).called(1);
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );

  testWidgets(
    'support screen builds from lightweight providers without aggregate loadData',
    (tester) async {
      await pumpScreen(tester, const SupportScreen());

      expect(find.text('Support Club'), findsOneWidget);
      expect(find.text('Active Causes'), findsOneWidget);

      verify(() => repository.getInitiatives('partner-1')).called(1);
      verify(() => repository.getActivePaymentRoute()).called(1);
      verifyNever(() => repository.getFanMembership('user-1', 'partner-1'));
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );

  testWidgets(
    'support detail screen builds from initiative and contributor providers only',
    (tester) async {
      await pumpScreen(
        tester,
        const SupportDetailScreen(initiativeId: 'initiative-1'),
      );

      expect(find.text('Support Club'), findsOneWidget);
      expect(find.text('Back this cause'), findsOneWidget);
      expect(find.text('More details'), findsOneWidget);
      expect(find.text('Jamie Supporter'), findsOneWidget);

      verify(() => repository.getInitiatives('partner-1')).called(1);
      verify(
        () => repository.getRecentContributionActivity('initiative-1', 10),
      ).called(1);
      verify(() => repository.getActivePaymentRoute()).called(1);
      verifyNever(() => repository.getFanMembership('user-1', 'partner-1'));
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );

  testWidgets(
    'shop checkout screen builds from lightweight shop providers on entry',
    (tester) async {
      final cartController = RayonCartController()..addToCart('product-1');

      await pumpScreen(
        tester,
        const ShopCheckoutScreen(),
        overrides: [
          rayonCartControllerProvider.overrideWith((ref) => cartController),
        ],
      );

      expect(find.text('Checkout'), findsOneWidget);
      expect(find.text('Review order'), findsOneWidget);
      expect(find.text('Pickup or delivery'), findsOneWidget);

      verify(() => repository.getProducts('partner-1', null)).called(1);
      verify(
        () => repository.getFanMembership('user-1', 'partner-1'),
      ).called(1);
      verify(() => repository.getActivePaymentRoute()).called(1);
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );
}
