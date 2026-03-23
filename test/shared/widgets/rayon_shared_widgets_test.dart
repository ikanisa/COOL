import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/shared/widgets/rs_digital_ticket.dart';
import 'package:cool_app/shared/widgets/rs_fan_club_card.dart';
import 'package:cool_app/shared/widgets/rs_initiative_card.dart';
import 'package:cool_app/shared/widgets/rs_amount_selector.dart';
import 'package:cool_app/shared/widgets/rs_club_card.dart';
import 'package:cool_app/shared/widgets/rs_league_table.dart';
import 'package:cool_app/shared/widgets/rs_match_card.dart';
import 'package:cool_app/shared/widgets/rs_membership_card.dart';
import 'package:cool_app/shared/widgets/rs_service_card.dart';
import 'package:cool_app/shared/widgets/rs_shop_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

RsMatch _sampleMatch({bool isOnSale = true, int soldCount = 2500}) => RsMatch(
  id: 'match-1',
  homeTeam: 'Rayon Sports FC',
  awayTeam: 'APR FC',
  competition: 'Rwanda Premier League',
  venue: 'Kigali Pelé Stadium',
  matchDate: DateTime(2026, 4, 18),
  kickoffTime: '18:00',
  isOnSale: isOnSale,
  ticketGeneralPrice: 3000,
  ticketVipPrice: 10000,
  saleStartsAt: DateTime(2026, 4, 10),
  capacity: 18000,
  soldCount: soldCount,
);

RsTicket _sampleTicket({TicketStatus status = TicketStatus.pending}) =>
    RsTicket(
      id: 'ticket-1',
      matchId: 'match-1',
      match: _sampleMatch(),
      userId: 'fan123456',
      seatType: SeatType.vip,
      amountPaid: 10000,
      qrCode: 'ticket-qr-code',
      momoReference: 'MOMO-123456',
      status: status,
      purchasedAt: DateTime(2026, 4, 12, 14, 30),
    );

const RsProduct _sampleProduct = RsProduct(
  id: 'product-1',
  partnerId: 'partner-1',
  name: 'Replica Jersey',
  description: 'Official home jersey for the current campaign.',
  category: ProductCategory.kits,
  price: 5000,
  imageEmoji: '👕',
  bgColor: Color(0xFF0D2878),
  stock: 12,
  isActive: true,
  isNew: true,
  availableSizes: <String>['S', 'M', 'L'],
  collection: 'Matchday',
);

const RsInitiative _sampleInitiative = RsInitiative(
  id: 'initiative-1',
  partnerId: 'partner-1',
  title: 'Youth Academy Expansion',
  description: 'Fund transport, kits, and training access for the next intake.',
  category: InitiativeCategory.youth,
  targetAmount: 1000000,
  raisedAmount: 125000,
  supporterCount: 42,
  isActive: true,
  endsAt: null,
);

const RsFanClub _sampleClub = RsFanClub(
  id: 'club-1',
  partnerId: 'partner-1',
  name: 'Kigali Blue',
  region: 'Kigali',
  description: 'Main chapter for city-wide watch parties and matchday support.',
  memberCount: 120,
  eventCount: 5,
  rating: 4.8,
  bannerEmoji: '🥁',
);

final RsFanMembership _sampleMembership = FanMembership(
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

const List<RsLeagueTeam> _sampleLeagueTeams = <RsLeagueTeam>[
  RsLeagueTeam(
    position: 1,
    name: 'Rayon Sports FC',
    played: 22,
    won: 16,
    points: 50,
    form: <String>['W', 'W', 'D', 'W', 'W'],
    isHighlighted: true,
  ),
  RsLeagueTeam(
    position: 2,
    name: 'APR FC',
    played: 22,
    won: 15,
    points: 47,
    form: <String>['W', 'D', 'W', 'L', 'W'],
  ),
];

void main() {
  group('Rayon shared widgets', () {
    testWidgets('RsMatchCard renders core match details and CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(RsMatchCard(match: _sampleMatch(), onBuyTap: () {})),
      );

      expect(find.text('BUY TICKET'), findsOneWidget);
      expect(find.text('Rayon Sports FC'), findsOneWidget);
      expect(find.text('APR FC'), findsOneWidget);
    });

    testWidgets('RsDigitalTicket renders ticket identity and status copy', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(RsDigitalTicket(ticket: _sampleTicket())));

      expect(find.text('Rayon Sports FC vs APR FC'), findsOneWidget);
      expect(find.text('MOMO-123456'), findsOneWidget);
      expect(
        find.textContaining('Payment is still pending confirmation'),
        findsOneWidget,
      );
    });

    testWidgets('RsShopItem renders merchandising details and cart CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RsShopItem(
            product: _sampleProduct,
            onAddToCart: () {},
            hasMemberDiscount: true,
            discountPct: 10,
            quantity: 1,
          ),
        ),
      );

      expect(find.text('Replica Jersey'), findsOneWidget);
      expect(find.text('ADD MORE'), findsOneWidget);
      expect(find.text('4,500 RWF'), findsOneWidget);
    });

    testWidgets('RsInitiativeCard renders funding progress and support CTA', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RsInitiativeCard(initiative: _sampleInitiative, onSupportTap: () {}),
        ),
      );

      expect(find.text('Youth Academy Expansion'), findsOneWidget);
      expect(find.text('SUPPORT'), findsOneWidget);
      expect(find.text('13%'), findsOneWidget);
    });

    testWidgets('RsFanClubCard renders joined state and chapter stats', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RsFanClubCard(club: _sampleClub, isJoined: true, onJoinTap: () {}),
        ),
      );

      expect(find.text('Kigali Blue'), findsOneWidget);
      expect(find.text('JOINED'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
    });

    testWidgets('RsClubCard renders club summary copy', (tester) async {
      await tester.pumpWidget(
        _wrap(RsClubCard(club: _sampleClub, joined: false, onTap: () {})),
      );

      expect(find.text('Kigali Blue'), findsOneWidget);
      expect(find.text('Kigali'), findsOneWidget);
      expect(find.text('120 members'), findsOneWidget);
    });

    testWidgets('RsAmountSelector supports preset and custom amounts', (
      tester,
    ) async {
      int? selectedAmount;

      await tester.pumpWidget(
        _wrap(
          RsAmountSelector(
            amounts: const <int>[1000, 2000, 5000],
            allowCustom: true,
            onAmountSelected: (value) => selectedAmount = value,
          ),
        ),
      );

      await tester.tap(find.text('1000 RWF'));
      await tester.pumpAndSettle();
      expect(selectedAmount, 1000);

      await tester.tap(find.text('Custom amount'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '7500');
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      expect(selectedAmount, 7500);
    });

    testWidgets('RsMembershipCard renders member identity and points', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(RsMembershipCard(membership: _sampleMembership)),
      );

      expect(find.text('RAYON SPORTS FC'), findsOneWidget);
      expect(find.text('Alex Fan'), findsOneWidget);
      expect(find.text('RS-2026-AAA111'), findsOneWidget);
      expect(find.text('2200'), findsOneWidget);
    });

    testWidgets('RsLeagueTable renders title and highlighted team row', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const RsLeagueTable(
            teams: _sampleLeagueTeams,
            seasonTitle: '2025/26 Season',
          ),
        ),
      );

      expect(find.text('LEAGUE STANDINGS'), findsOneWidget);
      expect(find.text('2025/26 Season'), findsOneWidget);
      expect(find.text('Rayon Sports FC'), findsOneWidget);
      expect(find.text('APR FC'), findsOneWidget);
    });

    testWidgets('RsServiceCard renders service summary and affordance', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RsServiceCard(
            icon: '🎟️',
            name: 'Ticket Office',
            desc: 'Manage on-sale fixtures and fan access.',
            count: '12 live fixtures',
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Ticket Office'), findsOneWidget);
      expect(find.text('12 live fixtures'), findsOneWidget);
      expect(find.text('Open service'), findsOneWidget);
    });
  });
}
