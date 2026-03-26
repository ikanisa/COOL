import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/screens/fan_profile_screen.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  late MockRayonSportsRepository repository;
  late UserProfile user;
  late RsFanMembership membership;
  late RsAchievement achievement;
  late RsTicket ticket;
  late RsShopOrder order;
  late RsMatch match;
  late RsProduct product;

  setUp(() {
    repository = MockRayonSportsRepository();
    user = const UserProfile(
      id: 'user-1',
      phone: '+250788123456',
      fullName: 'Alex Fan',
      publicUserId: '123456',
      momoNumber: '0788123456',
      momoProvider: 'mtn',
      country: 'RW',
      languageCode: 'en',
    );
    membership = FanMembership(
      id: 'membership-1',
      userId: 'user-1',
      partnerId: 'partner-1',
      displayName: '123456',
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
    order = RsShopOrder(
      id: 'order-1',
      userId: 'user-1',
      items: <CartItem>[
        CartItem(product: product, quantity: 1, selectedVariant: null),
      ],
      subtotal: 5000,
      discountAmount: 0,
      deliveryFee: 0,
      total: 5000,
      deliveryAddress: 'Kigali Heights',
      momoReference: 'order-momo-1',
      status: OrderStatus.confirmed,
      createdAt: DateTime(2026, 3, 20),
    );

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
    when(
      () => repository.getMyShopOrders('user-1'),
    ).thenAnswer((_) async => <RsShopOrder>[order]);
  });

  testWidgets(
    'fan profile uses lightweight profile providers without loading the full Rayon bundle',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rayonSportsRepositoryProvider.overrideWithValue(repository),
            rayonCurrentUserIdProvider.overrideWith((ref) => 'user-1'),
            rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
            currentUserProvider.overrideWith((ref) => user),
          ],
          child: const MaterialApp(home: FanProfileScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('123456'), findsWidgets);
      expect(find.text('RECENT ORDERS'), findsOneWidget);

      verify(
        () => repository.getFanMembership('user-1', 'partner-1'),
      ).called(1);
      verify(
        () => repository.getAchievements(
          userId: 'user-1',
          partnerId: 'partner-1',
        ),
      ).called(1);
      verify(() => repository.getMyShopOrders('user-1')).called(1);
      verifyNever(() => repository.loadData(userId: any(named: 'userId')));
    },
  );
}
