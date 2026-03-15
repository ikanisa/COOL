import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/features/partners/rayon/rayon_identity.dart';
import 'package:cool_app/features/partners/rayon/rayon_payment.dart';
import 'package:cool_app/features/partners/rayon/rayon_ticket_qr.dart';

/// QA-03: End-to-End Rayon Flow QA
///
/// Smoke-checks the model layer, identity constants, payment helpers,
/// and ticket status lifecycle used across membership, clubs, shop,
/// support, and ticketing.
void main() {
  setUp(() {
    debugSetRayonTicketQrSecretOverride('test-ticket-qr-secret');
  });

  tearDown(() {
    debugSetRayonTicketQrSecretOverride(null);
  });

  // ── Identity & Payment Constants ──────────────────────────────────

  group('Rayon identity', () {
    test('partner lookup names are non-empty', () {
      expect(rayonSportsPartnerLookupNames, isNotEmpty);
      for (final name in rayonSportsPartnerLookupNames) {
        expect(name, isNotEmpty);
      }
    });

    test('primary lookup name is Rayon Sports FC', () {
      expect(rayonSportsPartnerLookupNames.first, 'Rayon Sports FC');
    });
  });

  group('Rayon payment route', () {
    test('PartnerPaymentRoute.payToLabel formats correctly', () {
      const route = PartnerPaymentRoute(
        id: 'route-1',
        partnerId: 'rayon',
        partnerName: 'Rayon Sports FC',
        partnerSlug: 'rayon-sports',
        countryCode: 'RW',
        providerId: 'mtn_rwanda',
        recipientCode: '008000',
        reconciliationLabel: 'RAYON-SPORTS',
        status: PartnerPaymentRouteStatus.active,
      );

      expect(route.isActive, isTrue);
      expect(route.recipientCode, '008000');
      expect(route.payToLabel, contains('008000'));
    });

    test('PartnerPaymentRoute.ussdCode generates valid USSD', () {
      const route = PartnerPaymentRoute(
        id: 'route-2',
        partnerId: 'rayon',
        partnerName: 'Rayon Sports FC',
        partnerSlug: 'rayon-sports',
        countryCode: 'RW',
        providerId: 'mtn_rwanda',
        recipientCode: '008000',
        reconciliationLabel: 'RAYON-SPORTS',
        status: PartnerPaymentRouteStatus.active,
      );

      expect(route.ussdPattern, contains('[amount]'));
      expect(route.ussdPattern, contains('008000'));
      final ussd = route.ussdCode(5000);
      expect(ussd, contains('5000'));
      expect(ussd, startsWith('*182'));
      expect(ussd, endsWith('#'));
    });

    test('PartnerPaymentRoute.amountLabel formats amount', () {
      const route = PartnerPaymentRoute(
        id: 'route-3',
        partnerId: 'rayon',
        partnerName: 'Rayon Sports FC',
        partnerSlug: 'rayon-sports',
        countryCode: 'RW',
        providerId: 'mtn_rwanda',
        recipientCode: '008000',
        reconciliationLabel: 'RAYON-SPORTS',
        status: PartnerPaymentRouteStatus.active,
      );

      final label = route.amountLabel(12000);
      expect(label, contains('12,000'));
      expect(label, contains('RWF'));
    });

    test('inactive route returns isActive false', () {
      const route = PartnerPaymentRoute(
        id: 'route-4',
        partnerId: 'rayon',
        partnerName: 'Rayon Sports FC',
        partnerSlug: 'rayon-sports',
        countryCode: 'RW',
        providerId: 'mtn_rwanda',
        recipientCode: '008000',
        reconciliationLabel: 'RAYON-SPORTS',
        status: PartnerPaymentRouteStatus.draft,
      );

      expect(route.isActive, isFalse);
    });
  });

  // ── Fan Tier Lifecycle ────────────────────────────────────────────

  group('Fan tier system', () {
    test('FanTier enum has all expected values', () {
      expect(FanTier.values, hasLength(4));
      expect(
        FanTier.values.map((t) => t.name),
        containsAll(['blue', 'silver', 'gold', 'platinum']),
      );
    });

    test('FanTierX.fromPoints returns blue for < 1000 pts', () {
      expect(FanTierX.fromPoints(0), FanTier.blue);
      expect(FanTierX.fromPoints(999), FanTier.blue);
    });

    test('FanTierX.fromPoints returns silver for 1000-1999 pts', () {
      expect(FanTierX.fromPoints(1000), FanTier.silver);
      expect(FanTierX.fromPoints(1999), FanTier.silver);
    });

    test('FanTierX.fromPoints returns gold for 2000-4999 pts', () {
      expect(FanTierX.fromPoints(2000), FanTier.gold);
      expect(FanTierX.fromPoints(4999), FanTier.gold);
    });

    test('FanTierX.fromPoints returns platinum for >= 5000 pts', () {
      expect(FanTierX.fromPoints(5000), FanTier.platinum);
      expect(FanTierX.fromPoints(99999), FanTier.platinum);
    });

    test('tier promotion is monotonic (more points = higher tier)', () {
      final thresholds = [0, 500, 999, 1000, 1500, 2000, 3000, 5000, 10000];
      FanTier? previous;
      for (final pts in thresholds) {
        final tier = FanTierX.fromPoints(pts);
        if (previous != null) {
          expect(
            tier.index,
            greaterThanOrEqualTo(previous.index),
            reason: '$pts pts should have tier >= previous',
          );
        }
        previous = tier;
      }
    });
  });

  // ── Ticket Status Lifecycle ───────────────────────────────────────

  group('Ticket status lifecycle', () {
    test('buildRayonTicketQrData creates signed COOL ticket payload', () {
      final qrData = buildRayonTicketQrData(
        ticketId: 'ticket-1',
        matchId: 'match-1',
        purchasedAt: DateTime.utc(2026, 4, 1, 15),
      );

      expect(qrData, startsWith('COOL-TKT:'));
      expect(isSignedRayonTicketQr(qrData), isTrue);
    });

    test(
      'RsTicket qrData falls back to a signed payload when qrCode is legacy',
      () {
        final ticket = RsTicket(
          id: 'ticket-2',
          matchId: 'match-2',
          match: RsMatch(
            id: 'match-2',
            homeTeam: 'Rayon Sports FC',
            awayTeam: 'APR FC',
            competition: 'Rwanda Premier League',
            venue: 'Amahoro Stadium',
            matchDate: DateTime.utc(2026, 5, 1, 16),
            kickoffTime: '16:00',
            isOnSale: true,
            ticketGeneralPrice: 2000,
            ticketVipPrice: 5000,
            saleStartsAt: DateTime.utc(2026, 4, 20),
            capacity: 25000,
          ),
          userId: 'user-1',
          seatType: SeatType.general,
          amountPaid: 2000,
          qrCode: 'legacy-row-value',
          momoReference: 'REF-002',
          status: TicketStatus.pending,
          purchasedAt: DateTime.utc(2026, 5, 1, 16),
        );

        expect(ticket.status, TicketStatus.pending);
        expect(ticket.qrData, startsWith('COOL-TKT:'));
        expect(isSignedRayonTicketQr(ticket.qrData), isTrue);
      },
    );

    test('RsTicket preserves a stored signed qrCode', () {
      final signedQr = buildRayonTicketQrData(
        ticketId: 'ticket-3',
        matchId: 'match-3',
        purchasedAt: DateTime.utc(2026, 6, 1, 16),
      );
      final ticket = RsTicket(
        id: 'ticket-3',
        matchId: 'match-3',
        match: RsMatch(
          id: 'match-3',
          homeTeam: 'Rayon Sports FC',
          awayTeam: 'Kiyovu Sports',
          competition: 'Peace Cup',
          venue: 'Kigali Stadium',
          matchDate: DateTime.utc(2026, 6, 1, 16),
          kickoffTime: '16:00',
          isOnSale: true,
          ticketGeneralPrice: 1500,
          ticketVipPrice: 4000,
          saleStartsAt: DateTime.utc(2026, 5, 20),
          capacity: 18000,
        ),
        userId: 'user-2',
        seatType: SeatType.vip,
        amountPaid: 4000,
        qrCode: signedQr,
        momoReference: 'REF-003',
        status: TicketStatus.valid,
        purchasedAt: DateTime.utc(2026, 6, 1, 16),
      );

      expect(ticket.qrData, signedQr);
    });
  });

  // ── Model Serialization Smoke Checks ──────────────────────────────

  group('RsFanClub model', () {
    test('fromJson round-trip works', () {
      final json = <String, dynamic>{
        'id': 'club-1',
        'partner_id': 'partner-1',
        'name': 'Kigali Blues',
        'region': 'Kigali',
        'member_count': 42,
      };
      final club = RsFanClub.fromJson(json);
      expect(club.id, 'club-1');
      expect(club.name, 'Kigali Blues');
      expect(club.region, 'Kigali');
      expect(club.memberCount, 42);
    });
  });

  group('RsMatch model', () {
    test('fromJson parses match data', () {
      final json = <String, dynamic>{
        'id': 'match-1',
        'partner_id': 'partner-1',
        'home_team': 'Rayon Sports FC',
        'away_team': 'APR FC',
        'competition': 'Rwanda Premier League',
        'venue': 'Amahoro Stadium',
        'match_date': '2026-04-01T15:00:00Z',
        'kickoff_time': '15:00',
        'is_on_sale': true,
        'ticket_general_price': 2000,
        'ticket_vip_price': 5000,
        'sale_starts_at': '2026-03-25T00:00:00Z',
        'capacity': 25000,
      };
      final match = RsMatch.fromJson(json);
      expect(match.id, 'match-1');
      expect(match.awayTeam, 'APR FC');
      expect(match.venue, 'Amahoro Stadium');
      expect(match.ticketGeneralPrice, 2000);
      expect(match.ticketVipPrice, 5000);
      expect(match.isOnSale, isTrue);
    });
  });

  group('RsShopProduct model', () {
    test('fromJson parses product data', () {
      final json = <String, dynamic>{
        'id': 'prod-1',
        'partner_id': 'partner-1',
        'name': 'Rayon Jersey 2026',
        'price': 15000,
        'category': 'jerseys',
        'is_active': true,
      };
      final product = RsShopProduct.fromJson(json);
      expect(product.id, 'prod-1');
      expect(product.name, 'Rayon Jersey 2026');
      expect(product.price, 15000);
    });
  });

  group('RsShopOrder model', () {
    test(
      'paid and fulfilled backend statuses map to active UI order states',
      () {
        final paidOrder = RsShopOrder.fromJson(const <String, dynamic>{
          'id': 'order-1',
          'user_id': 'user-1',
          'items': <Map<String, dynamic>>[],
          'subtotal': 10000,
          'discount': 0,
          'total': 10000,
          'delivery_address': 'Kigali',
          'momo_reference': 'RS-SHOP-1',
          'status': 'paid',
          'created_at': '2026-03-10T12:00:00Z',
        });
        final fulfilledOrder = RsShopOrder.fromJson(const <String, dynamic>{
          'id': 'order-2',
          'user_id': 'user-1',
          'items': <Map<String, dynamic>>[],
          'subtotal': 10000,
          'discount': 0,
          'total': 10000,
          'delivery_address': 'Kigali',
          'momo_reference': 'RS-SHOP-2',
          'status': 'fulfilled',
          'created_at': '2026-03-10T12:00:00Z',
        });

        expect(paidOrder.status, OrderStatus.confirmed);
        expect(fulfilledOrder.status, OrderStatus.delivered);
      },
    );
  });

  group('RsInitiative model', () {
    test('fromJson parses initiative data', () {
      final json = <String, dynamic>{
        'id': 'init-1',
        'partner_id': 'partner-1',
        'title': 'Youth Academy Fund',
        'description': 'Supporting youth development',
        'category': 'youth',
        'target_amount': 5000000,
        'raised_amount': 1200000,
        'supporter_count': 150,
        'is_active': true,
        'ends_at': '2026-12-31T00:00:00Z',
      };
      final initiative = RsInitiative.fromJson(json);
      expect(initiative.id, 'init-1');
      expect(initiative.title, 'Youth Academy Fund');
      expect(initiative.targetAmount, 5000000);
      expect(initiative.raisedAmount, 1200000);
      expect(initiative.progressPercent, closeTo(24.0, 0.1));
    });
  });

  group('RsInitiative progress', () {
    test('0 target returns 0 progress', () {
      final json = <String, dynamic>{
        'id': 'init-0',
        'partner_id': 'partner-1',
        'title': 'Zero Target',
        'description': '',
        'category': 'community',
        'target_amount': 0,
        'raised_amount': 1000,
        'supporter_count': 5,
        'is_active': true,
      };
      final initiative = RsInitiative.fromJson(json);
      expect(initiative.progressPercent, 0);
    });

    test('over-funded caps at 100%', () {
      final json = <String, dynamic>{
        'id': 'init-over',
        'partner_id': 'partner-1',
        'title': 'Over Funded',
        'description': '',
        'category': 'community',
        'target_amount': 1000,
        'raised_amount': 5000,
        'supporter_count': 100,
        'is_active': true,
      };
      final initiative = RsInitiative.fromJson(json);
      expect(initiative.progressPercent, 100);
    });
  });
}
