import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/rayon_payment.dart';
import 'package:cool_app/features/partners/rayon/screens/my_tickets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RsTicket buildTicket({required TicketStatus status}) {
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
    return RsTicket(
      id: 'ticket-1',
      matchId: 'match-1',
      match: match,
      userId: 'user-1',
      seatType: SeatType.general,
      amountPaid: 3000,
      qrCode: 'qr-1',
      momoReference: 'momo-1',
      status: status,
      purchasedAt: DateTime(2026, 3, 25),
    );
  }

  testWidgets('my tickets shows empty-state browse action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rayonUserTicketsProvider.overrideWith((ref) async => <RsTicket>[]),
          rayonPaymentRouteProvider.overrideWith(
            (ref) async => const PartnerPaymentRoute(
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
          ),
        ],
        child: const MaterialApp(home: MyTicketsScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No tickets yet'), findsOneWidget);
    expect(find.text('Browse Matches'), findsOneWidget);
  });

  testWidgets(
    'my tickets keeps pending payment messaging honest when route is unavailable',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rayonUserTicketsProvider.overrideWith(
              (ref) async => <RsTicket>[
                buildTicket(status: TicketStatus.pending),
              ],
            ),
            rayonPaymentRouteProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: MyTicketsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('PAYMENT PENDING'), findsOneWidget);
      expect(
        find.text('Awaiting payment. QR unlocks after confirmation.'),
        findsOneWidget,
      );
    },
  );
}
