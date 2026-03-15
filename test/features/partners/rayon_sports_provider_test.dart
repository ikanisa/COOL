import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/rayon_payment.dart';

import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  late MockRayonSportsRepository repository;
  late RayonSportsData data;
  late RsMatch match;
  late RsProduct product;
  late RsInitiative initiative;
  late PartnerPaymentRoute paymentRoute;

  setUp(() {
    repository = MockRayonSportsRepository();
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
    product = const RsProduct(
      id: 'prod-1',
      partnerId: 'rayon',
      name: 'Replica Jersey',
      category: ProductCategory.kits,
      price: 5000,
      imageEmoji: '👕',
      bgColor: Colors.blue,
      stock: 20,
      isActive: true,
      isNew: false,
    );
    initiative = const RsInitiative(
      id: 'init-1',
      partnerId: 'rayon',
      title: 'Youth Academy',
      description: 'Back the academy',
      category: InitiativeCategory.youth,
      targetAmount: 500000,
      raisedAmount: 120000,
      supporterCount: 12,
      isActive: true,
      endsAt: null,
    );
    paymentRoute = const PartnerPaymentRoute(
      id: 'route-1',
      partnerId: 'rayon',
      partnerName: 'Rayon Sports FC',
      partnerSlug: 'rayon-sports',
      countryCode: 'RW',
      providerId: 'mtn_rwanda',
      recipientCode: '008000',
      reconciliationLabel: 'rayon_sports',
      status: PartnerPaymentRouteStatus.active,
    );
    data = RayonSportsData(
      partnerId: 'rayon',
      membership: FanMembership(
        id: 'membership-1',
        userId: 'user-1',
        partnerId: 'rayon',
        displayName: 'Rayon Fan',
        tier: FanTier.gold,
        points: 2200,
        chapter: 'Kigali',
        membershipNumber: 'RS-2026-AAA111',
        joinedAt: DateTime(2026, 1, 1),
      ),
      joinedClubIds: const <String>{},
      registryMembers: const <RsRegistryMember>[],
      achievements: const <RsAchievement>[],
      clubs: const <RsFanClub>[
        RsFanClub(
          id: 'club-1',
          partnerId: 'rayon',
          name: 'Kigali Blue',
          region: 'Kigali',
          description: 'Main chapter',
          memberCount: 100,
          eventCount: 5,
          rating: 4.8,
          bannerEmoji: '🥁',
        ),
      ],
      products: <RsProduct>[product],
      initiatives: <RsInitiative>[initiative],
      matches: <RsMatch>[match],
      tickets: const <RsTicket>[],
    );

    when(
      () => repository.loadData(userId: 'user-1'),
    ).thenAnswer((_) async => data);
    when(
      () => repository.getActivePaymentRoute(),
    ).thenAnswer((_) async => paymentRoute);
  });

  group('RayonSportsNotifier smoke', () {
    test('loads membership data', () async {
      final notifier = RayonSportsNotifier(
        repository: repository,
        userId: 'user-1',
        autoLoad: false,
      );

      await notifier.load();

      expect(notifier.state.data.value?.membership, isNotNull);
      expect(
        notifier.state.data.value?.membership?.membershipNumber,
        'RS-2026-AAA111',
      );
      verify(() => repository.loadData(userId: 'user-1')).called(1);
    });

    test('restores existing membership without creating a duplicate', () async {
      final membership = data.membership!;
      when(
        () => repository.getRayonFanMembership('user-1'),
      ).thenAnswer((_) async => membership);

      final notifier = RayonSportsNotifier(
        repository: repository,
        userId: 'user-1',
        autoLoad: false,
      );

      await notifier.load();
      final result = await notifier.ensureMembership();

      expect(result.created, isFalse);
      expect(result.membership.membershipNumber, membership.membershipNumber);
      expect(
        notifier.state.action.value,
        'Official Rayon membership restored.',
      );
      verify(() => repository.getRayonFanMembership('user-1')).called(1);
      verifyNever(() => repository.createFanMembership('user-1'));
      verify(() => repository.loadData(userId: 'user-1')).called(2);
    });

    test('creates membership when none exists yet', () async {
      final membership = data.membership!;
      when(
        () => repository.getRayonFanMembership('user-1'),
      ).thenAnswer((_) async => null);
      when(
        () => repository.createFanMembership('user-1'),
      ).thenAnswer((_) async => membership);

      final notifier = RayonSportsNotifier(
        repository: repository,
        userId: 'user-1',
        autoLoad: false,
      );

      await notifier.load();
      final result = await notifier.ensureMembership();

      expect(result.created, isTrue);
      expect(result.membership.membershipNumber, membership.membershipNumber);
      expect(notifier.state.action.value, 'Official Rayon membership created.');
      verify(() => repository.getRayonFanMembership('user-1')).called(1);
      verify(() => repository.createFanMembership('user-1')).called(1);
      verify(() => repository.loadData(userId: 'user-1')).called(2);
    });

    test('joins clubs and refreshes data', () async {
      when(
        () => repository.joinClub(clubId: 'club-1', userId: 'user-1'),
      ).thenAnswer((_) async {});

      final notifier = RayonSportsNotifier(
        repository: repository,
        userId: 'user-1',
        autoLoad: false,
      );

      await notifier.load();
      final message = await notifier.joinClub('club-1');

      expect(message, 'Fan club joined.');
      expect(notifier.state.action.value, 'Fan club joined.');
      verify(
        () => repository.joinClub(clubId: 'club-1', userId: 'user-1'),
      ).called(1);
      verify(() => repository.loadData(userId: 'user-1')).called(2);
    });

    test('opens ticket checkout flow and refreshes data', () async {
      when(
        () => repository.purchaseTickets(
          matchId: 'match-1',
          userId: 'user-1',
          seatType: 'VIP',
          quantity: 2,
        ),
      ).thenAnswer((_) async => const <RsTicket>[]);

      final notifier = RayonSportsNotifier(
        repository: repository,
        userId: 'user-1',
        autoLoad: false,
      );

      await notifier.load();
      final message = await notifier.buyTicket(
        match: match,
        seatType: 'VIP',
        quantity: 2,
      );

      expect(
        message,
        'Ticket checkout opened to MTN MoMo code 008000 for 12,000 RWF. Fees 0 RWF. Your tickets stay pending until SMS confirmation matches rayon_sports.',
      );
      verify(() => repository.getActivePaymentRoute()).called(1);
      verify(
        () => repository.purchaseTickets(
          matchId: 'match-1',
          userId: 'user-1',
          seatType: 'VIP',
          quantity: 2,
        ),
      ).called(1);
      verify(() => repository.loadData(userId: 'user-1')).called(2);
    });

    test('opens support checkout flow and refreshes data', () async {
      when(
        () => repository.supportInitiative(
          userId: 'user-1',
          initiativeId: 'init-1',
          amount: 4500,
        ),
      ).thenAnswer((_) async => 'contrib-1');

      final notifier = RayonSportsNotifier(
        repository: repository,
        userId: 'user-1',
        autoLoad: false,
      );

      await notifier.load();
      final result = await notifier.supportInitiative(
        initiativeId: 'init-1',
        amount: 4500,
      );

      expect(result.contributionId, 'contrib-1');
      expect(result.amount, 4500);
      expect(
        result.message,
        'Support checkout opened to MTN MoMo code 008000 for 4,500 RWF. Fees 0 RWF. We confirm your receipt after SMS reconciliation for rayon_sports.',
      );
      verify(() => repository.getActivePaymentRoute()).called(1);
      verify(
        () => repository.supportInitiative(
          userId: 'user-1',
          initiativeId: 'init-1',
          amount: 4500,
        ),
      ).called(1);
      verify(() => repository.loadData(userId: 'user-1')).called(2);
    });

    test(
      'checks out shop orders, applies member discount, and clears cart',
      () async {
        when(
          () => repository.placeOrder(
            userId: 'user-1',
            products: [product],
            quantities: {'prod-1': 2},
            deliveryAddress: 'Kigali Heights',
            discountAmount: 1000,
          ),
        ).thenAnswer((_) async => 'order-1');

        final notifier = RayonSportsNotifier(
          repository: repository,
          userId: 'user-1',
          autoLoad: false,
        );

        await notifier.load();
        notifier.addToCart('prod-1');
        notifier.addToCart('prod-1');

        final result = await notifier.checkoutShop(
          products: [product],
          membership: data.membership,
          quantities: const {'prod-1': 2},
          deliveryAddress: 'Kigali Heights',
        );

        expect(result.orderId, 'order-1');
        expect(result.total, 9000);
        expect(
          result.message,
          'Shop checkout opened to MTN MoMo code 008000 for 9,000 RWF. Fees 0 RWF. Your order receipt appears after SMS reconciliation for rayon_sports.',
        );
        expect(notifier.cartItemCount(), 0);
        verify(() => repository.getActivePaymentRoute()).called(1);
        verify(
          () => repository.placeOrder(
            userId: 'user-1',
            products: [product],
            quantities: {'prod-1': 2},
            deliveryAddress: 'Kigali Heights',
            discountAmount: 1000,
          ),
        ).called(1);
        verify(() => repository.loadData(userId: 'user-1')).called(2);
      },
    );
  });
}
