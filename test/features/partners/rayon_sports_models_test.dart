import 'package:flutter_test/flutter_test.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:cool_app/shared/widgets/rs_league_table.dart';

void main() {
  group('FanTierX', () {
    test('fromValue parses known tiers', () {
      expect(FanTierX.fromValue('silver'), FanTier.silver);
      expect(FanTierX.fromValue('gold'), FanTier.gold);
      expect(FanTierX.fromValue('platinum'), FanTier.platinum);
      expect(FanTierX.fromValue('blue'), FanTier.blue);
    });

    test('fromValue falls back to blue for unknown/null', () {
      expect(FanTierX.fromValue(null), FanTier.blue);
      expect(FanTierX.fromValue('invalid'), FanTier.blue);
      expect(FanTierX.fromValue(''), FanTier.blue);
    });

    test('fromValue is case-insensitive', () {
      expect(FanTierX.fromValue('GOLD'), FanTier.gold);
      expect(FanTierX.fromValue('Silver'), FanTier.silver);
      expect(FanTierX.fromValue('PLATINUM'), FanTier.platinum);
    });

    test('fromPoints returns correct tier boundaries', () {
      expect(FanTierX.fromPoints(0), FanTier.blue);
      expect(FanTierX.fromPoints(999), FanTier.blue);
      expect(FanTierX.fromPoints(1000), FanTier.silver);
      expect(FanTierX.fromPoints(1999), FanTier.silver);
      expect(FanTierX.fromPoints(2000), FanTier.gold);
      expect(FanTierX.fromPoints(4999), FanTier.gold);
      expect(FanTierX.fromPoints(5000), FanTier.platinum);
      expect(FanTierX.fromPoints(10000), FanTier.platinum);
    });

    test('label returns readable string', () {
      expect(FanTier.blue.label, 'Blue');
      expect(FanTier.gold.label, 'Gold');
    });

    test('minPoints matches fromPoints boundaries', () {
      expect(FanTier.blue.minPoints, 0);
      expect(FanTier.silver.minPoints, 1000);
      expect(FanTier.gold.minPoints, 2000);
      expect(FanTier.platinum.minPoints, 5000);
    });
  });

  group('TicketStatusX', () {
    test('fromValue parses known statuses', () {
      expect(TicketStatusX.fromValue('valid'), TicketStatus.valid);
      expect(TicketStatusX.fromValue('used'), TicketStatus.used);
      expect(TicketStatusX.fromValue('cancelled'), TicketStatus.cancelled);
      expect(TicketStatusX.fromValue('voided'), TicketStatus.voided);
      expect(TicketStatusX.fromValue('refunded'), TicketStatus.refunded);
    });

    test('fromValue defaults to pending for unknown/null', () {
      expect(TicketStatusX.fromValue(null), TicketStatus.pending);
      expect(TicketStatusX.fromValue('unknown'), TicketStatus.pending);
    });

    test('label returns readable string', () {
      expect(TicketStatus.pending.label, 'Pending');
      expect(TicketStatus.valid.label, 'Valid');
      expect(TicketStatus.used.label, 'Used');
      expect(TicketStatus.cancelled.label, 'Cancelled');
      expect(TicketStatus.voided.label, 'Voided');
      expect(TicketStatus.refunded.label, 'Refunded');
    });

    test('isTerminal identifies terminal statuses', () {
      expect(TicketStatus.pending.isTerminal, false);
      expect(TicketStatus.valid.isTerminal, false);
      expect(TicketStatus.used.isTerminal, true);
      expect(TicketStatus.cancelled.isTerminal, true);
      expect(TicketStatus.voided.isTerminal, true);
      expect(TicketStatus.refunded.isTerminal, true);
    });
  });

  group('RsFanMembership.fromJson', () {
    test('parses fully-populated JSON', () {
      final json = {
        'id': 'mem-1',
        'user_id': 'user-1',
        'partner_id': 'rs',
        'display_name': 'Alice',
        'membership_number': 'RS-001',
        'points': 3200,
        'chapter': 'Huye',
        'joined_at': '2024-01-15T10:00:00Z',
        'tier': 'gold',
      };

      final m = FanMembership.fromJson(json);
      expect(m.id, 'mem-1');
      expect(m.userId, 'user-1');
      expect(m.displayName, 'Alice');
      expect(m.points, 3200);
      expect(m.chapter, 'Huye');
      expect(m.tier, FanTier.gold);
      expect(m.joinedAt.year, 2024);
    });

    test('handles missing fields with defaults', () {
      final m = FanMembership.fromJson(const <String, dynamic>{});
      expect(m.id, '');
      expect(m.displayName, 'Fan');
      expect(m.points, 0);
      expect(m.tier, FanTier.blue);
      expect(m.chapter, 'Kigali Central');
    });

    test('reads display_name from nested users fallback', () {
      final m = FanMembership.fromJson(const {
        'users': {'full_name': 'Nested Name'},
      });
      expect(m.displayName, 'Nested Name');
    });
  });

  group('RsInitiative', () {
    test('progress computes correctly', () {
      const init = RsInitiative(
        id: '1',
        partnerId: 'rs',
        title: 'Test',
        description: '',
        category: InitiativeCategory.community,
        targetAmount: 1000,
        raisedAmount: 500,
        supporterCount: 10,
        isActive: true,
        endsAt: null,
      );
      expect(init.progress, closeTo(0.5, 0.001));
    });

    test('progress is 0 when target <= 0', () {
      const init = RsInitiative(
        id: '2',
        partnerId: 'rs',
        title: 'Empty',
        description: '',
        category: InitiativeCategory.community,
        targetAmount: 0,
        raisedAmount: 100,
        supporterCount: 0,
        isActive: false,
        endsAt: null,
      );
      expect(init.progress, 0);
    });

    test('progress clamps to 1 when over-funded', () {
      const init = RsInitiative(
        id: '3',
        partnerId: 'rs',
        title: 'Over',
        description: '',
        category: InitiativeCategory.community,
        targetAmount: 100,
        raisedAmount: 200,
        supporterCount: 5,
        isActive: true,
        endsAt: null,
      );
      expect(init.progress, 1.0);
    });
  });

  group('RsMatch', () {
    test('title combines home and away teams', () {
      final match = RsMatch.fromJson(const {
        'home_team': 'Rayon Sports',
        'away_team': 'APR FC',
        'match_date': '2026-04-10',
      });
      expect(
        '${match.homeTeam} vs ${match.awayTeam}',
        'Rayon Sports vs APR FC',
      );
    });

    test('kickoff time is truncated to 5 chars if longer', () {
      final match = RsMatch.fromJson(const {'kickoff_time': '15:00:00'});
      expect(match.kickoffTime, '15:00');
    });
  });

  group('RsShopProduct.fromJson', () {
    test('parses price and stock as integers', () {
      final p = RsProduct.fromJson(const {
        'id': 'p-1',
        'name': 'Jersey',
        'price': 18000,
        'stock': 42,
      });
      expect(p.price, 18000);
      expect(p.stock, 42);
    });

    test('accepts numeric types (double price)', () {
      final p = RsProduct.fromJson(const {'price': 15000.5, 'stock': 10.0});
      expect(p.price, 15000);
      expect(p.stock, 10);
    });
  });

  group('OrderStatusX', () {
    test('fromValue parses all distinct statuses', () {
      expect(OrderStatusX.fromValue('pending'), OrderStatus.pending);
      expect(OrderStatusX.fromValue('paid'), OrderStatus.paid);
      expect(OrderStatusX.fromValue('confirmed'), OrderStatus.confirmed);
      expect(OrderStatusX.fromValue('packed'), OrderStatus.packed);
      expect(OrderStatusX.fromValue('shipped'), OrderStatus.shipped);
      expect(OrderStatusX.fromValue('fulfilled'), OrderStatus.fulfilled);
      expect(OrderStatusX.fromValue('delivered'), OrderStatus.delivered);
      expect(OrderStatusX.fromValue('cancelled'), OrderStatus.cancelled);
    });

    test('fromValue defaults to pending for unknown/null', () {
      expect(OrderStatusX.fromValue(null), OrderStatus.pending);
      expect(OrderStatusX.fromValue('xyz'), OrderStatus.pending);
    });

    test('labels are readable', () {
      expect(OrderStatus.paid.label, 'Paid');
      expect(OrderStatus.packed.label, 'Packed');
      expect(OrderStatus.fulfilled.label, 'Fulfilled');
    });

    test('isActive identifies active vs terminal statuses', () {
      expect(OrderStatus.pending.isActive, true);
      expect(OrderStatus.paid.isActive, true);
      expect(OrderStatus.confirmed.isActive, true);
      expect(OrderStatus.packed.isActive, true);
      expect(OrderStatus.shipped.isActive, true);
      expect(OrderStatus.fulfilled.isActive, false);
      expect(OrderStatus.delivered.isActive, false);
      expect(OrderStatus.cancelled.isActive, false);
    });
  });

  group('RsShopOrder', () {
    test('fromJson parses partnerId', () {
      final order = RsShopOrder.fromJson(const {
        'id': 'ord-1',
        'user_id': 'usr-1',
        'partner_id': 'partner-abc',
        'items': [],
        'subtotal': 5000,
        'total': 5000,
        'status': 'paid',
        'created_at': '2026-03-01T00:00:00Z',
      });
      expect(order.partnerId, 'partner-abc');
      expect(order.status, OrderStatus.paid);
    });

    test('partnerId is null when missing', () {
      final order = RsShopOrder.fromJson(const {
        'id': 'ord-2',
        'user_id': 'usr-2',
        'items': [],
        'total': 1000,
      });
      expect(order.partnerId, isNull);
    });
  });

  // RayonSportsData.demo() removed — repository uses _fallbackData() now

  group('RsLeagueTeam', () {
    test('constructor sets all fields', () {
      const team = RsLeagueTeam(
        position: 1,
        name: 'Test FC',
        played: 20,
        won: 15,
        points: 48,
        form: ['W', 'W', 'D', 'W', 'L'],
      );
      expect(team.position, 1);
      expect(team.name, 'Test FC');
      expect(team.played, 20);
      expect(team.won, 15);
      expect(team.points, 48);
      expect(team.form.length, 5);
      expect(team.isHighlighted, false);
    });

    test('isHighlighted defaults to false', () {
      const team = RsLeagueTeam(
        position: 2,
        name: 'Another FC',
        played: 10,
        won: 5,
        points: 18,
        form: ['W', 'D', 'L', 'W', 'W'],
      );
      expect(team.isHighlighted, false);
    });

    test('isHighlighted can be set to true', () {
      const team = RsLeagueTeam(
        position: 1,
        name: 'Highlighted FC',
        played: 10,
        won: 8,
        points: 26,
        form: ['W', 'W', 'W', 'D', 'W'],
        isHighlighted: true,
      );
      expect(team.isHighlighted, true);
    });
  });
}
