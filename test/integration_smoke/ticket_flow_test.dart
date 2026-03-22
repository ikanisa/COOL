import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/repositories/rayon_sports_repository.dart';
import 'package:cool_app/features/partners/rayon/screens/tickets_screen.dart';

import 'test_harness.dart';

class MockRayonSportsRepository extends Mock implements RayonSportsRepository {}

void main() {
  late MockRayonSportsRepository repository;
  late RsFanMembership membership;
  late RsMatch match;
  late RsTicket ticket;

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
      matchId: match.id,
      match: match,
      userId: 'user-1',
      seatType: SeatType.general,
      amountPaid: 3000,
      qrCode: 'qr-1',
      momoReference: 'momo-1',
      status: TicketStatus.valid,
      purchasedAt: DateTime(2026, 3, 25),
    );

    when(
      () => repository.getFanMembership('user-1', 'partner-1'),
    ).thenAnswer((_) async => membership);
    when(
      () => repository.getMatches('partner-1', false),
    ).thenAnswer((_) async => <RsMatch>[match]);
    when(
      () => repository.getMyTickets('user-1'),
    ).thenAnswer((_) async => <RsTicket>[ticket]);
  });

  testWidgets('Ticket hub renders the premium hero and tabs', (tester) async {
    await pumpScopedApp(
      tester,
      child: const TicketsScreen(),
      session: fakeSession(),
      user: fakeUser(),
      overrides: <Override>[
        rayonSportsRepositoryProvider.overrideWithValue(repository),
        rayonCurrentUserIdProvider.overrideWith((ref) => 'user-1'),
        rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
      ],
    );

    expect(find.text('Tickets'), findsOneWidget);
    expect(find.textContaining('On Sale'), findsOneWidget);
    expect(find.text('My Tickets'), findsOneWidget);
  });

  testWidgets('Ticket hub shows the on-sale fixture details', (tester) async {
    await pumpScopedApp(
      tester,
      child: const TicketsScreen(),
      session: fakeSession(),
      user: fakeUser(),
      overrides: <Override>[
        rayonSportsRepositoryProvider.overrideWithValue(repository),
        rayonCurrentUserIdProvider.overrideWith((ref) => 'user-1'),
        rayonPartnerIdProvider.overrideWith((ref) async => 'partner-1'),
      ],
    );

    expect(find.text('Rayon Sports'), findsOneWidget);
    expect(find.text('APR FC'), findsOneWidget);
    expect(find.text('Amahoro'), findsOneWidget);
    expect(find.textContaining('3,000'), findsWidgets);
  });
}
