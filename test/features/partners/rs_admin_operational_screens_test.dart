import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/providers/rs_admin_provider.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_matches_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_shop_screen.dart';
import 'package:cool_app/features/partners/rayon/screens/rs_admin_tickets_screen.dart';

import '../../helpers/google_fonts_test_assets.dart';
import '../../integration_smoke/test_harness.dart';

void main() {
  setUp(setUpBundledGoogleFonts);

  tearDown(tearDownBundledGoogleFonts);

  final match = RsMatch(
    id: 'match-1',
    homeTeam: 'Rayon Sports',
    awayTeam: 'APR FC',
    competition: 'RPL',
    venue: 'Amahoro Stadium',
    matchDate: DateTime(2026, 4, 1),
    kickoffTime: '18:00',
    isOnSale: true,
    ticketGeneralPrice: 3000,
    ticketVipPrice: 6000,
    saleStartsAt: DateTime(2026, 3, 20),
    capacity: 1200,
  );

  final ticket = RsTicket(
    id: 'ticket-1',
    matchId: 'match-1',
    match: match,
    userId: 'user-1',
    seatType: SeatType.general,
    amountPaid: 3000,
    qrCode: 'qr-1',
    momoReference: 'momo-1',
    status: TicketStatus.valid,
    purchasedAt: DateTime(2026, 3, 25, 13, 45),
  );

  const product = RsProduct(
    id: 'product-1',
    partnerId: 'partner-1',
    name: 'Replica Jersey',
    category: ProductCategory.kits,
    price: 5000,
    imageEmoji: '👕',
    bgColor: Color(0xFF0A57B7),
    stock: 4,
    isActive: true,
    isNew: false,
    description: 'Official home jersey',
  );

  testWidgets('admin matches screen renders redesigned operational tile', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const RsAdminMatchesScreen(),
      user: fakeUser(isAdmin: true),
      session: fakeSession(
        appMetadata: const <String, dynamic>{'is_admin': true},
      ),
      overrides: [
        rsAdminMatchesProvider.overrideWith((ref) async => <RsMatch>[match]),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Matches'), findsWidgets);
    expect(find.text('RAYON SPORTS COMMAND'), findsOneWidget);
    expect(find.text('Rayon Sports vs APR FC'), findsOneWidget);
    expect(find.text('ON SALE'), findsWidgets);
  });

  testWidgets('admin tickets screen renders redesigned ticket controls', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const RsAdminTicketsScreen(),
      user: fakeUser(isAdmin: true),
      session: fakeSession(
        appMetadata: const <String, dynamic>{'is_admin': true},
      ),
      overrides: [
        rsAdminMatchesProvider.overrideWith((ref) async => <RsMatch>[match]),
        rsAdminTicketsProvider(
          null,
        ).overrideWith((ref) async => <RsTicket>[ticket]),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Tickets'), findsWidgets);
    expect(find.text('RAYON SPORTS COMMAND'), findsOneWidget);
    expect(find.text('Gate Check'), findsOneWidget);
    expect(find.text('VALID'), findsWidgets);
  });

  testWidgets('admin shop screen renders redesigned product controls', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const RsAdminShopScreen(),
      user: fakeUser(isAdmin: true),
      session: fakeSession(
        appMetadata: const <String, dynamic>{'is_admin': true},
      ),
      overrides: [
        rsAdminProductsProvider.overrideWith(
          (ref) async => <RsProduct>[product],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Shop Products'), findsWidgets);
    expect(find.text('RAYON SPORTS COMMAND'), findsOneWidget);
    expect(find.text('Replica Jersey'), findsOneWidget);
    expect(find.text('Low stock'), findsOneWidget);
  });
}
