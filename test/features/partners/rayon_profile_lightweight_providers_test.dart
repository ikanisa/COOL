import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  late MockRayonSportsRepository repository;
  late RsFanMembership membership;
  late RsAchievement achievement;
  late RsTicket ticket;
  late RsMatch match;
  late RsFanClub club;
  late RsProduct product;
  late RsInitiative initiative;

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        rayonSportsRepositoryProvider.overrideWithValue(repository),
        rayonCurrentUserIdProvider.overrideWith((ref) => 'user-1'),
        rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
      ],
    );
    addTearDown(container.dispose);
    return container;
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
    achievement = RsAchievement(
      id: 'achievement-1',
      userId: 'user-1',
      badgeType: 'loyalty',
      emoji: '🏆',
      name: 'Loyal Supporter',
      description: 'Attended multiple matches.',
      isEarned: true,
      earnedAt: DateTime(2026, 2, 1),
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
    club = const RsFanClub(
      id: 'club-1',
      partnerId: 'partner-1',
      name: 'Kigali Blue',
      region: 'Kigali',
      description: 'Main chapter',
      memberCount: 150,
      eventCount: 8,
      rating: 4.9,
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
      stock: 24,
      isActive: true,
      isNew: false,
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
  });

  test('lightweight profile providers use discrete repository calls', () async {
    when(
      () => repository.getFanMembership('user-1', 'partner-1'),
    ).thenAnswer((_) async => membership);
    when(
      () =>
          repository.getAchievements(userId: 'user-1', partnerId: 'partner-1'),
    ).thenAnswer((_) async => <RsAchievement>[achievement]);
    when(
      () => repository.getMyTickets('user-1'),
    ).thenAnswer((_) async => <RsTicket>[ticket]);

    final container = createContainer();

    expect(
      await container.read(rayonUserMembershipProvider.future),
      membership,
    );
    expect(
      await container.read(rayonUserAchievementsProvider.future),
      <RsAchievement>[achievement],
    );
    expect(await container.read(rayonUserTicketsProvider.future), <RsTicket>[
      ticket,
    ]);

    verify(() => repository.getFanMembership('user-1', 'partner-1')).called(1);
    verify(
      () =>
          repository.getAchievements(userId: 'user-1', partnerId: 'partner-1'),
    ).called(1);
    verify(() => repository.getMyTickets('user-1')).called(1);
    verifyNever(() => repository.loadData(userId: any(named: 'userId')));
  });

  test('ticket lookup reads from lightweight ticket data', () async {
    when(
      () => repository.getMyTickets('user-1'),
    ).thenAnswer((_) async => <RsTicket>[ticket]);

    final container = createContainer();

    await container.read(rayonUserTicketsProvider.future);

    expect(
      container.read(rayonUserTicketByIdProvider('ticket-1')).valueOrNull?.id,
      'ticket-1',
    );
    verify(() => repository.getMyTickets('user-1')).called(1);
  });

  test(
    'clubs, shop, tickets, and support providers avoid aggregate loadData',
    () async {
      when(
        () => repository.getFanMembership('user-1', 'partner-1'),
      ).thenAnswer((_) async => membership);
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
        () => repository.getMatches('partner-1', false),
      ).thenAnswer((_) async => <RsMatch>[match]);
      when(
        () => repository.getMyTickets('user-1'),
      ).thenAnswer((_) async => <RsTicket>[ticket]);
      when(
        () => repository.getInitiatives('partner-1'),
      ).thenAnswer((_) async => <RsInitiative>[initiative]);
      when(
        () => repository.getAchievements(
          userId: 'user-1',
          partnerId: 'partner-1',
        ),
      ).thenAnswer((_) async => <RsAchievement>[achievement]);

      final container = createContainer();

      await container.read(rayonFanClubsProvider.future);
      await container.read(rayonJoinedClubIdsProvider.future);
      await container.read(rayonShopProductsProvider.future);
      await container.read(rayonMatchesProvider.future);
      await container.read(rayonInitiativesProvider.future);
      await container.read(rayonUserMembershipProvider.future);
      await container.read(rayonUserTicketsProvider.future);
      await container.read(rayonUserAchievementsProvider.future);

      expect(
        container.read(rayonClubDirectoryProvider).valueOrNull?.joinedClubIds,
        <String>{'club-1'},
      );
      expect(
        container.read(rayonClubDetailProvider('club-1')).valueOrNull?.club?.id,
        'club-1',
      );
      expect(
        container.read(rayonShopCatalogProvider).valueOrNull?.products,
        <RsProduct>[product],
      );
      expect(
        container.read(rayonTicketHubProvider).valueOrNull?.tickets,
        <RsTicket>[ticket],
      );
      expect(
        container
            .read(rayonInitiativesSummaryProvider)
            .valueOrNull
            ?.activeCauses,
        1,
      );

      verify(() => repository.getUserClubs('user-1')).called(1);
      verify(() => repository.getFanClubs('partner-1', null)).called(1);
      verify(() => repository.getProducts('partner-1', null)).called(1);
      verify(() => repository.getMatches('partner-1', false)).called(1);
      verify(() => repository.getInitiatives('partner-1')).called(1);
      verify(
        () => repository.getFanMembership('user-1', 'partner-1'),
      ).called(1);
      verify(
        () => repository.getAchievements(
          userId: 'user-1',
          partnerId: 'partner-1',
        ),
      ).called(1);
      verify(() => repository.getMyTickets('user-1')).called(1);
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );

  test('cart controller updates without touching aggregate Rayon state', () {
    final container = createContainer();
    final controller = container.read(rayonCartControllerProvider.notifier);

    controller.addToCart('product-1');
    controller.addToCart('product-1');
    controller.removeFromCart('product-1');

    expect(container.read(rayonCartProvider), <String, int>{'product-1': 1});
    verifyNever(() => repository.loadData(userId: any(named: 'userId')));
  });
}
