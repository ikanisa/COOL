import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/screens/rayon/ticket_confirmation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ticket confirmation does not expose deferred Google Wallet actions',
    (tester) async {
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
        purchasedAt: DateTime(2026, 3, 25),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rayonUserTicketsProvider.overrideWith(
              (ref) async => <RsTicket>[ticket],
            ),
          ],
          child: const MaterialApp(
            home: TicketConfirmationScreen(ticketId: 'ticket-1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Ticket'), findsOneWidget);
      expect(find.text('Valid Ticket'), findsOneWidget);
      expect(find.text('Back to Tickets'), findsOneWidget);
      expect(find.text('Add to Google Wallet'), findsNothing);
      expect(
        find.text('Google Wallet is not enabled for this environment yet.'),
        findsNothing,
      );
    },
  );
}
