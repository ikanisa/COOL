import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/identity/public_user_identity.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/services/operational_health_service.dart';
import '../rayon/rayon_identity.dart';
import '../rayon/models/rs_models.dart';
import '../rayon/rayon_payment.dart';
import '../rayon/rayon_ticket_qr.dart';

class RayonSportsRepository {
  RayonSportsRepository({
    SupabaseClient? client,
    MomoService? momoService,
    OperationalHealthService? operationalHealthService,
  }) : _client = client ?? Supabase.instance.client,
       _momoService = momoService ?? MomoService.instance,
       _operationalHealthService =
           operationalHealthService ??
           OperationalHealthService(client: client ?? Supabase.instance.client);

  final SupabaseClient _client;
  final MomoService _momoService;
  final OperationalHealthService _operationalHealthService;
  PartnerPaymentRoute? _cachedPaymentRoute;

  Future<RayonSportsData> loadData({String? userId}) async {
    try {
      final partnerId = await _resolvePartnerId();
      if (partnerId == null) {
        debugPrint('[RayonRepo] ⚠️ Partner not found in database');
        throw StateError(
          'Rayon Sports partner not found. '
          'Ensure seed data has been applied.',
        );
      }

      final membershipRowsFuture = _client
          .from('rs_fan_memberships')
          .select()
          .eq('partner_id', partnerId)
          .order('points', ascending: false);
      final joinedClubRowsFuture = userId == null
          ? Future.value(const <Map<String, dynamic>>[])
          : _client
                .from('rs_fan_club_members')
                .select('club_id')
                .eq('user_id', userId)
                .then(_asListOfMaps);
      final achievementsRowsFuture = userId == null
          ? Future.value(const <Map<String, dynamic>>[])
          : _client
                .from('rs_achievements')
                .select()
                .eq('partner_id', partnerId)
                .eq('user_id', userId)
                .order('earned_at', ascending: false)
                .then(_asListOfMaps);
      final clubsRowsFuture = _client
          .from('rs_fan_clubs')
          .select()
          .eq('partner_id', partnerId)
          .order('member_count', ascending: false);
      final productsRowsFuture = _client
          .from('rs_shop_products')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true)
          .order('price');
      final initiativesRowsFuture = _client
          .from('rs_initiatives')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true)
          .order('ends_at');
      final matchesRowsFuture = _client
          .from('rs_matches')
          .select()
          .eq('partner_id', partnerId)
          .order('match_date');

      final rawMembershipRows = await membershipRowsFuture;
      final membershipRows = _asListOfMaps(rawMembershipRows);
      final joinedClubRows = await joinedClubRowsFuture;
      final achievementsRows = await achievementsRowsFuture;
      final rawClubsRows = await clubsRowsFuture;
      final rawProductsRows = await productsRowsFuture;
      final rawInitiativesRows = await initiativesRowsFuture;
      final rawMatchesRows = await matchesRowsFuture;

      final joinedClubIds = joinedClubRows
          .map((row) => row['club_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      final registry = membershipRows
          .map(
            (row) => RsRegistryMember.fromJson(_withResolvedDisplayName(row)),
          )
          .toList(growable: false);

      Map<String, dynamic>? currentMembership;
      if (userId != null) {
        for (final row in membershipRows) {
          if (row['user_id']?.toString() == userId) {
            currentMembership = row;
            break;
          }
        }
      }

      final achievements = achievementsRows
          .map(RsAchievement.fromJson)
          .toList(growable: false);

      final clubs = _asListOfMaps(
        rawClubsRows,
      ).map(RsFanClub.fromJson).toList(growable: false);

      final products = _asListOfMaps(
        rawProductsRows,
      ).map(RsShopProduct.fromJson).toList(growable: false);

      final initiatives = _asListOfMaps(
        rawInitiativesRows,
      ).map(RsInitiative.fromJson).toList(growable: false);

      final matches = _asListOfMaps(
        rawMatchesRows,
      ).map(RsMatch.fromJson).toList(growable: false);

      final matchesById = <String, RsMatch>{
        for (final match in matches) match.id: match,
      };

      final ticketRows = userId == null
          ? const <Map<String, dynamic>>[]
          : _asListOfMaps(
              await _client
                  .from('rs_tickets')
                  .select()
                  .eq('user_id', userId)
                  .order('purchased_at', ascending: false),
            );
      final tickets = ticketRows
          .map((row) {
            final match = matchesById[row['match_id']?.toString()];
            return RsTicket.fromJson(<String, dynamic>{
              ...row,
              'match': match?.toJson(),
              'fan_id': currentMembership?['membership_number'],
            });
          })
          .toList(growable: false);

      if (membershipRows.isEmpty &&
          clubs.isEmpty &&
          products.isEmpty &&
          initiatives.isEmpty &&
          matches.isEmpty &&
          tickets.isEmpty) {
        debugPrint(
          '[RayonRepo] ⚠️ All Rayon tables are empty for '
          'partner $partnerId — returning empty state',
        );
      }

      final membership = currentMembership == null
          ? null
          : RsFanMembership.fromJson(
              _withResolvedDisplayName(currentMembership),
            );

      return RayonSportsData(
        partnerId: partnerId,
        membership: membership,
        joinedClubIds: joinedClubIds,
        registryMembers: registry,
        achievements: achievements,
        clubs: clubs,
        products: products,
        initiatives: initiatives,
        matches: matches,
        tickets: tickets,
      );
    } catch (error, stack) {
      debugPrint('[RayonRepo] ❌ loadData failed: $error');
      debugPrint('[RayonRepo] $stack');
      rethrow;
    }
  }

  Future<void> joinClub({
    required String clubId,
    required String userId,
  }) async {
    await _client.from('rs_fan_club_members').upsert(<String, dynamic>{
      'club_id': clubId,
      'user_id': userId,
    }, onConflict: 'club_id,user_id');
  }

  /// Leave a fan club.
  Future<void> leaveClub({
    required String clubId,
    required String userId,
  }) async {
    await _client
        .from('rs_fan_club_members')
        .delete()
        .eq('club_id', clubId)
        .eq('user_id', userId);
  }

  /// Get all clubs a user has joined, with club details.
  Future<List<RsFanClub>> getUserClubs(String userId) async {
    final memberRows = _asListOfMaps(
      await _client
          .from('rs_fan_club_members')
          .select('club_id')
          .eq('user_id', userId),
    );
    if (memberRows.isEmpty) return const [];

    final clubIds = memberRows
        .map((r) => r['club_id']?.toString() ?? '')
        .toList();
    return _asListOfMaps(
      await _client.from('rs_fan_clubs').select().inFilter('id', clubIds),
    ).map(RsFanClub.fromJson).toList(growable: false);
  }

  Future<String> supportInitiative({
    required String userId,
    required String initiativeId,
    required int amount,
    String? referralInviteId,
  }) async {
    if (amount <= 0) {
      throw StateError('Support amount must be greater than zero.');
    }

    final paymentRoute = await getActivePaymentRoute();
    final reference = 'RS-SUPPORT-${DateTime.now().millisecondsSinceEpoch}';

    try {
      final rows = _asListOfMaps(
        await _client
            .from('rs_initiative_contributions')
            .insert(<String, dynamic>{
              'initiative_id': initiativeId,
              'user_id': userId,
              'amount': amount,
              'momo_reference': reference,
              'referral_invite_id': referralInviteId,
              'status': 'pending',
            })
            .select('id'),
      );

      final contributionId = rows.first['id']?.toString() ?? reference;
      await _launchRayonMomoPayment(
        amount: amount,
        reference: reference,
        route: paymentRoute,
      );
      await _recordPartnerCheckoutEvent(
        component: 'rayon_support',
        userId: userId,
        subjectType: 'rs_initiative_contributions',
        subjectId: contributionId,
        reference: reference,
        message: 'Rayon support checkout opened successfully.',
        metadata: <String, dynamic>{
          'initiative_id': initiativeId,
          'amount': amount,
        },
      );
      return contributionId;
    } catch (error) {
      await _recordPartnerCheckoutEvent(
        component: 'rayon_support',
        userId: userId,
        status: OperationalHealthStatus.error,
        issueCode: 'partner_checkout_failed',
        reference: reference,
        message: 'Rayon support checkout failed before payment sync.',
        metadata: <String, dynamic>{
          'initiative_id': initiativeId,
          'amount': amount,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  // ── Fan Membership ─────────────────────────────────────────────────

  Future<String?> getRayonPartnerId() {
    return _resolvePartnerId();
  }

  Future<PartnerPaymentRoute> getActivePaymentRoute({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cachedRoute = _cachedPaymentRoute;
      if (cachedRoute != null && cachedRoute.isActive) {
        return cachedRoute;
      }
    }

    final partner = await _resolvePartnerSummary();
    final partnerId = partner['id']?.toString().trim() ?? '';
    if (partnerId.isEmpty) {
      throw StateError('Rayon Sports partner record was not found.');
    }

    final routePayload = await _client.rpc(
      'get_partner_payment_route',
      params: <String, dynamic>{
        'p_partner_id': partnerId,
        'p_country': partner['country']?.toString(),
      },
    );

    final routeData = _asMap(routePayload);
    final paymentRoute = PartnerPaymentRoute.fromJson(routeData);
    if (!paymentRoute.isActive) {
      throw StateError(
        'Rayon Sports payment routing is not active for ${paymentRoute.countryCode}.',
      );
    }
    if (paymentRoute.recipientCode.isEmpty) {
      throw StateError(
        'Rayon Sports payment routing is missing a recipient code.',
      );
    }

    _cachedPaymentRoute = paymentRoute;
    return paymentRoute;
  }

  Future<bool> isGoogleWalletOperationallyReady() async {
    try {
      final response = await _client.functions.invoke(
        'wallet-issuer',
        body: const <String, dynamic>{'action': 'health'},
      );
      final data = _asMap(response.data);
      return data['success'] == true && data['configured'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<RsFanMembership?> getRayonFanMembership(String userId) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null || partnerId.isEmpty) {
      return null;
    }
    return getFanMembership(userId, partnerId);
  }

  /// Get a user's fan membership for a given partner.
  Future<RsFanMembership?> getFanMembership(
    String userId,
    String partnerId,
  ) async {
    final row = await _client
        .from('rs_fan_memberships')
        .select()
        .eq('partner_id', partnerId)
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return null;
    return RsFanMembership.fromJson(_withResolvedDisplayName(_asMap(row)));
  }

  Future<List<RsAchievement>> getAchievements({
    required String userId,
    required String partnerId,
  }) async {
    return _asListOfMaps(
      await _client
          .from('rs_achievements')
          .select()
          .eq('partner_id', partnerId)
          .eq('user_id', userId)
          .order('earned_at', ascending: false),
    ).map(RsAchievement.fromJson).toList(growable: false);
  }

  /// Create a new fan membership (tier: blue, points: 0).
  Future<RsFanMembership> createFanMembership(
    String userId, {
    String? partnerId,
  }) async {
    final resolvedPartnerId = partnerId ?? await _resolvePartnerId();
    if (resolvedPartnerId == null || resolvedPartnerId.isEmpty) {
      throw StateError('Rayon Sports partner record was not found.');
    }

    final membershipNumber =
        'RS-1968-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    final row = _asListOfMaps(
      await _client.from('rs_fan_memberships').insert(<String, dynamic>{
        'user_id': userId,
        'partner_id': resolvedPartnerId,
        'display_name': _displayNameForUser(userId),
        'tier': 'blue',
        'points': 0,
        'membership_number': membershipNumber,
        'chapter': 'Kigali Central',
      }).select(),
    ).first;

    return RsFanMembership.fromJson(_withResolvedDisplayName(row));
  }

  /// Add points to a user's membership and re-evaluate tier.
  Future<RsFanMembership> addPoints(
    String userId,
    String partnerId,
    int points,
    String reason,
  ) async {
    // Fetch current
    final current = await _client
        .from('rs_fan_memberships')
        .select()
        .eq('partner_id', partnerId)
        .eq('user_id', userId)
        .single();

    final currentPoints = (current['points'] as num?)?.toInt() ?? 0;
    final newPoints = currentPoints + points;
    final newTier = FanTierX.fromPoints(newPoints);

    final updated = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, dynamic>{
            'points': newPoints,
            'tier': newTier.name,
            'display_name': _displayNameForUser(userId),
          })
          .eq('partner_id', partnerId)
          .eq('user_id', userId)
          .select(),
    ).first;

    return RsFanMembership.fromJson(_withResolvedDisplayName(updated));
  }

  // ── Registry ───────────────────────────────────────────────────────

  /// Query the member registry with search, tier filter, and pagination.
  Future<List<RsRegistryMember>> getMembers(
    String partnerId, {
    String? searchQuery,
    FanTier? filterTier,
    String? region,
    int limit = 20,
    int offset = 0,
  }) async {
    if (partnerId.isEmpty) {
      return const <RsRegistryMember>[];
    }

    final rows = _asListOfMaps(
      await _client.rpc(
        'get_rayon_member_registry',
        params: <String, dynamic>{
          'p_partner_id': partnerId,
          'p_search_query': _nullIfBlank(searchQuery),
          'p_filter_tier': filterTier?.name,
          'p_region': _nullIfBlank(region),
          'p_limit': limit,
          'p_offset': offset,
        },
      ),
    );

    return rows.map(RsRegistryMember.fromJson).toList(growable: false);
  }

  // ── Fan Clubs ──────────────────────────────────────────────────────

  /// Get fan clubs for a partner, optionally filtered by region.
  Future<List<RsFanClub>> getFanClubs(String partnerId, String? region) async {
    var query = _client
        .from('rs_fan_clubs')
        .select()
        .eq('partner_id', partnerId);

    if (region != null && region.isNotEmpty) {
      query = query.ilike('region', '%$region%');
    }

    return _asListOfMaps(
      await query.order('member_count', ascending: false),
    ).map(RsFanClub.fromJson).toList(growable: false);
  }

  // ── Matches & Tickets ──────────────────────────────────────────────

  /// Get matches, optionally filtering to on-sale only.
  Future<List<RsMatch>> getMatches(String partnerId, bool onSaleOnly) async {
    var query = _client.from('rs_matches').select().eq('partner_id', partnerId);

    if (onSaleOnly) {
      query = query.eq('is_on_sale', true);
    }

    return _asListOfMaps(
      await query.order('match_date'),
    ).map(RsMatch.fromJson).toList(growable: false);
  }

  /// Create one or more pending Rayon tickets under a single payment reference.
  /// Membership points are awarded only after backend confirmation.
  Future<List<RsTicket>> purchaseTickets({
    required String matchId,
    required String userId,
    required String seatType,
    required int quantity,
    String? referralInviteId,
  }) async {
    final paymentRoute = await getActivePaymentRoute();
    final match = _asListOfMaps(
      await _client.from('rs_matches').select().eq('id', matchId),
    ).map(RsMatch.fromJson).first;

    final normalizedSeat = seatType.toLowerCase() == 'vip' ? 'VIP' : 'General';
    final unitPrice = normalizedSeat == 'VIP'
        ? match.ticketVipPrice
        : match.ticketGeneralPrice;
    final paymentReference =
        'RS-TICKET-${DateTime.now().millisecondsSinceEpoch}';

    final totalAmount = unitPrice * quantity;
    try {
      final inserts = <Map<String, dynamic>>[];
      for (var i = 0; i < quantity; i++) {
        inserts.add(<String, dynamic>{
          'match_id': matchId,
          'user_id': userId,
          'seat_type': normalizedSeat,
          'amount_paid': unitPrice,
          'qr_code': null,
          'momo_reference': paymentReference,
          'referral_invite_id': referralInviteId,
          'status': 'pending',
        });
      }

      final rows = _asListOfMaps(
        await _client.from('rs_tickets').insert(inserts).select(),
      );

      // Points are awarded by the backend (parse-momo-sms) after SMS
      // payment confirmation — do NOT award client-side.
      await _launchRayonMomoPayment(
        amount: totalAmount,
        reference: paymentReference,
        route: paymentRoute,
      );

      final tickets = rows
          .map((row) {
            final ticket = RsTicket.fromJson(<String, dynamic>{
              ...row,
              'match': match.toJson(),
            });
            return ticket.copyWith(qrCode: _ticketQrCodeFor(ticket));
          })
          .toList(growable: false);

      await _recordPartnerCheckoutEvent(
        component: 'rayon_ticket',
        userId: userId,
        subjectType: 'rs_tickets',
        subjectId: tickets.isEmpty ? null : tickets.first.id,
        reference: paymentReference,
        message: 'Rayon ticket checkout opened successfully.',
        metadata: <String, dynamic>{
          'match_id': matchId,
          'quantity': quantity,
          'seat_type': normalizedSeat,
          'amount': totalAmount,
        },
      );

      return tickets;
    } catch (error) {
      await _recordPartnerCheckoutEvent(
        component: 'rayon_ticket',
        userId: userId,
        status: OperationalHealthStatus.error,
        issueCode: 'partner_checkout_failed',
        reference: paymentReference,
        message: 'Rayon ticket checkout failed before payment sync.',
        metadata: <String, dynamic>{
          'match_id': matchId,
          'quantity': quantity,
          'seat_type': normalizedSeat,
          'amount': totalAmount,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  /// Get all tickets for a user, enriched with match data.
  Future<List<RsTicket>> getMyTickets(String userId) async {
    final ticketRows = _asListOfMaps(
      await _client
          .from('rs_tickets')
          .select()
          .eq('user_id', userId)
          .order('purchased_at', ascending: false),
    );

    if (ticketRows.isEmpty) return const [];

    final matchIds = ticketRows
        .map((r) => r['match_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final matchRows = _asListOfMaps(
      await _client.from('rs_matches').select().inFilter('id', matchIds),
    );
    final matchesById = <String, RsMatch>{
      for (final m in matchRows.map(RsMatch.fromJson)) m.id: m,
    };

    return ticketRows
        .map((row) {
          final match = matchesById[row['match_id']?.toString()];
          return RsTicket.fromJson(<String, dynamic>{
            ...row,
            'match': match?.toJson(),
          });
        })
        .toList(growable: false);
  }

  /// Cancel a pending ticket. Only tickets with status 'pending' are cancellable.
  Future<void> cancelTicket(String ticketId) async {
    await _client
        .from('rs_tickets')
        .update(<String, dynamic>{'status': 'cancelled'})
        .eq('id', ticketId)
        .eq('status', 'pending');
  }

  Future<String> createGoogleWalletSaveUrl({required String ticketId}) async {
    final response = await _client.functions.invoke(
      'wallet-issuer',
      body: <String, dynamic>{'action': 'rayon_ticket', 'ticketId': ticketId},
    );

    final data = _asMap(response.data);
    if (data['success'] != true) {
      throw StateError(
        data['message']?.toString() ??
            'Failed to prepare the Google Wallet pass.',
      );
    }

    final saveUrl = data['saveUrl']?.toString().trim() ?? '';
    if (saveUrl.isEmpty) {
      throw StateError('Wallet issuer did not return a save URL.');
    }

    return saveUrl;
  }

  // ── Shop ───────────────────────────────────────────────────────────

  /// Get products, optionally filtered by category.
  Future<List<RsShopProduct>> getProducts(
    String partnerId,
    String? category,
  ) async {
    var query = _client
        .from('rs_shop_products')
        .select()
        .eq('partner_id', partnerId)
        .eq('is_active', true);

    if (category != null && category.isNotEmpty) {
      query = query.ilike('category', '%$category%');
    }

    return _asListOfMaps(
      await query.order('sort_order').order('price').order('name'),
    ).map(RsShopProduct.fromJson).toList(growable: false);
  }

  /// Place a shop order. Returns the generated order ID.
  Future<String> placeOrder({
    required String userId,
    required List<RsShopProduct> products,
    required Map<String, int> quantities,
    required String deliveryAddress,
    String? referralInviteId,
    int discountAmount = 0,
  }) async {
    final paymentRoute = await getActivePaymentRoute();
    final subtotal = _sumProducts(products, quantities);
    if (subtotal <= 0) throw StateError('Your cart is empty.');

    final total = subtotal - discountAmount;
    final reference = 'RS-SHOP-${DateTime.now().millisecondsSinceEpoch}';

    try {
      final rows = _asListOfMaps(
        await _client
            .from('rs_shop_orders')
            .insert(<String, dynamic>{
              'user_id': userId,
              'items': products
                  .map(
                    (p) => <String, dynamic>{
                      'product': p.toJson(),
                      'product_id': p.id,
                      'name': p.name,
                      'category': p.category.value,
                      'image_emoji': p.imageEmoji,
                      'image_url': p.imageUrl,
                      'bg_color':
                          '#${p.bgColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                      'sizes': p.availableSizes,
                      'quantity': quantities[p.id] ?? 0,
                      'unit_price': p.price,
                    },
                  )
                  .where((item) => (item['quantity'] as int) > 0)
                  .toList(growable: false),
              'subtotal': subtotal,
              'discount_amount': discountAmount,
              'discount': discountAmount,
              'delivery_fee': 0,
              'total': total,
              'delivery_address': deliveryAddress,
              'momo_reference': reference,
              'referral_invite_id': referralInviteId,
              'status': 'pending',
            })
            .select('id'),
      );

      final orderId = rows.first['id']?.toString() ?? reference;
      await _launchRayonMomoPayment(
        amount: total,
        reference: reference,
        route: paymentRoute,
      );
      await _recordPartnerCheckoutEvent(
        component: 'rayon_shop',
        userId: userId,
        subjectType: 'rs_shop_orders',
        subjectId: orderId,
        reference: reference,
        message: 'Rayon shop checkout opened successfully.',
        metadata: <String, dynamic>{
          'item_count': quantities.values.fold<int>(
            0,
            (sum, quantity) => sum + quantity,
          ),
          'discount_amount': discountAmount,
          'total': total,
        },
      );
      return orderId;
    } catch (error) {
      await _recordPartnerCheckoutEvent(
        component: 'rayon_shop',
        userId: userId,
        status: OperationalHealthStatus.error,
        issueCode: 'partner_checkout_failed',
        reference: reference,
        message: 'Rayon shop checkout failed before payment sync.',
        metadata: <String, dynamic>{
          'discount_amount': discountAmount,
          'total': total,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  /// Get all orders for a user.
  Future<List<Map<String, dynamic>>> getMyOrders(String userId) async {
    return _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    );
  }

  Future<List<RsShopOrder>> getMyShopOrders(String userId) async {
    return _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    ).map(RsShopOrder.fromJson).toList(growable: false);
  }

  /// Cancel a pending shop order.
  Future<void> cancelOrder(String orderId) async {
    await _client
        .from('rs_shop_orders')
        .update(<String, dynamic>{'status': 'cancelled'})
        .eq('id', orderId)
        .eq('status', 'pending');
  }

  // ── Initiatives ────────────────────────────────────────────────────

  /// Get active initiatives for a partner.
  Future<List<RsInitiative>> getInitiatives(String partnerId) async {
    return _asListOfMaps(
      await _client
          .from('rs_initiatives')
          .select()
          .eq('partner_id', partnerId)
          .eq('is_active', true)
          .order('ends_at'),
    ).map(RsInitiative.fromJson).toList(growable: false);
  }

  /// Contribute to an initiative. Returns the contribution ID.
  Future<String> contribute({
    required String initiativeId,
    required String userId,
    required int amount,
    String? referralInviteId,
  }) async {
    if (amount <= 0) {
      throw StateError('Contribution amount must be greater than zero.');
    }

    final paymentRoute = await getActivePaymentRoute();
    final reference = 'RS-SUPPORT-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final rows = _asListOfMaps(
        await _client
            .from('rs_initiative_contributions')
            .insert(<String, dynamic>{
              'initiative_id': initiativeId,
              'user_id': userId,
              'amount': amount,
              'momo_reference': reference,
              'referral_invite_id': referralInviteId,
              'status': 'pending',
            })
            .select('id'),
      );

      final contributionId = rows.first['id']?.toString() ?? reference;
      await _launchRayonMomoPayment(
        amount: amount,
        reference: reference,
        route: paymentRoute,
      );
      await _recordPartnerCheckoutEvent(
        component: 'rayon_support',
        userId: userId,
        subjectType: 'rs_initiative_contributions',
        subjectId: contributionId,
        reference: reference,
        message: 'Rayon initiative checkout opened successfully.',
        metadata: <String, dynamic>{
          'initiative_id': initiativeId,
          'amount': amount,
        },
      );
      return contributionId;
    } catch (error) {
      await _recordPartnerCheckoutEvent(
        component: 'rayon_support',
        userId: userId,
        status: OperationalHealthStatus.error,
        issueCode: 'partner_checkout_failed',
        reference: reference,
        message: 'Rayon initiative checkout failed before payment sync.',
        metadata: <String, dynamic>{
          'initiative_id': initiativeId,
          'amount': amount,
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  /// Get recent contributors for an initiative.
  Future<List<Map<String, dynamic>>> getRecentContributors(
    String initiativeId,
    int limit,
  ) async {
    return (await getRecentContributionActivity(initiativeId, limit))
        .map(
          (contribution) => <String, dynamic>{
            'id': contribution.id,
            'userId': contribution.userId,
            'name': contribution.supporterName ?? 'Supporter',
            'amount': contribution.amount,
            'createdAt': contribution.createdAt.toIso8601String(),
            'status': contribution.status,
            'momoReference': contribution.momoReference,
          },
        )
        .toList(growable: false);
  }

  Future<List<RsInitiativeContribution>> getRecentContributionActivity(
    String initiativeId,
    int limit,
  ) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_initiative_contributions')
          .select(
            'id, user_id, amount, created_at, status, momo_reference, supporter_name',
          )
          .eq('initiative_id', initiativeId)
          .order('created_at', ascending: false)
          .limit(limit),
    );

    if (rows.isEmpty) return const [];

    return rows
        .map(
          (row) => RsInitiativeContribution.fromJson(<String, dynamic>{
            ...row,
            'initiative_id': initiativeId,
            'supporter_name': _supporterNameForRow(row),
          }),
        )
        .toList(growable: false);
  }

  // ── Helpers ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _resolvePartnerSummary() async {
    try {
      final slugRow = await _client
          .from('partners')
          .select('id, slug, name, country')
          .eq('slug', 'rayon-sports')
          .limit(1)
          .maybeSingle();
      final slugPartner = _asMapOrNull(slugRow);
      if (slugPartner != null) {
        final slugId = slugPartner['id']?.toString().trim() ?? '';
        if (slugId.isNotEmpty) {
          return slugPartner;
        }
      }
    } on PostgrestException catch (_) {
      // Older environments may not have the slug column yet.
    }

    final exactMatches = _asListOfMaps(
      await _client
          .from('partners')
          .select('id, slug, name, country')
          .inFilter('name', rayonSportsPartnerLookupNames),
    );
    final preferredMatch = _pickPreferredRayonPartner(exactMatches);
    if (preferredMatch != null) {
      return preferredMatch;
    }

    final fallbackRow = await _client
        .from('partners')
        .select('id, slug, name, country')
        .ilike('name', 'Rayon Sports%')
        .maybeSingle();
    return _asMapOrNull(fallbackRow) ?? const <String, dynamic>{};
  }

  Future<String?> _resolvePartnerId() async {
    final partner = await _resolvePartnerSummary();
    final partnerId = partner['id']?.toString().trim();
    if (partnerId == null || partnerId.isEmpty) {
      return null;
    }
    return partnerId;
  }

  Map<String, dynamic>? _pickPreferredRayonPartner(
    List<Map<String, dynamic>> rows,
  ) {
    for (final row in rows) {
      final slug = row['slug']?.toString();
      final id = row['id']?.toString().trim() ?? '';
      if (slug == 'rayon-sports' && id.isNotEmpty) {
        return row;
      }
    }

    for (final partnerName in rayonSportsPartnerLookupNames) {
      for (final row in rows) {
        if (row['name']?.toString() == partnerName) {
          final id = row['id']?.toString().trim() ?? '';
          if (id.isNotEmpty) {
            return row;
          }
        }
      }
    }
    return null;
  }

  int _sumProducts(List<RsShopProduct> products, Map<String, int> quantities) {
    var total = 0;
    for (final product in products) {
      total += product.price * (quantities[product.id] ?? 0);
    }
    return total;
  }

  String _ticketQrCodeFor(RsTicket ticket) {
    return buildRayonTicketQrData(
      ticketId: ticket.id,
      matchId: ticket.matchId,
      purchasedAt: ticket.purchasedAt,
    );
  }

  Future<void> _launchRayonMomoPayment({
    required int amount,
    required String reference,
    required PartnerPaymentRoute route,
  }) {
    return _momoService.initiateUSSD(
      amount: amount,
      reference: reference,
      countryCode: route.countryCode,
      recipientMomo: route.recipientCode,
      recipientType: MomoRecipientType.code,
    );
  }

  Future<void> _recordPartnerCheckoutEvent({
    required String component,
    required String userId,
    required String message,
    OperationalHealthStatus status = OperationalHealthStatus.ok,
    String? issueCode,
    String? subjectType,
    String? subjectId,
    String? reference,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    return _operationalHealthService.recordEvent(
      service: 'partner_checkout',
      component: component,
      status: status,
      issueCode: issueCode,
      message: message,
      userId: userId,
      subjectType: subjectType,
      subjectId: subjectId,
      metadata: <String, dynamic>{'reference': reference, ...metadata},
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // ADMIN — Match CRUD
  // ══════════════════════════════════════════════════════════════════════

  /// Get ALL matches (including off-sale), for admin listing.
  Future<List<RsMatch>> adminGetAllMatches() async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) return const <RsMatch>[];
    return _asListOfMaps(
      await _client
          .from('rs_matches')
          .select()
          .eq('partner_id', partnerId)
          .order('match_date', ascending: false),
    ).map(RsMatch.fromJson).toList(growable: false);
  }

  /// Create a new match.
  Future<RsMatch> createMatch({
    required String homeTeam,
    required String awayTeam,
    required String competition,
    required String venue,
    required DateTime matchDate,
    required String kickoffTime,
    required int ticketGeneralPrice,
    required int ticketVipPrice,
    required int capacity,
    required DateTime saleStartsAt,
    bool isOnSale = false,
  }) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final row = _asListOfMaps(
      await _client.from('rs_matches').insert(<String, dynamic>{
        'partner_id': partnerId,
        'home_team': homeTeam,
        'away_team': awayTeam,
        'competition': competition,
        'venue': venue,
        'match_date': matchDate.toIso8601String(),
        'kickoff_time': kickoffTime,
        'ticket_general_price': ticketGeneralPrice,
        'ticket_vip_price': ticketVipPrice,
        'capacity': capacity,
        'sale_starts_at': saleStartsAt.toIso8601String(),
        'is_on_sale': isOnSale,
        'sold_count': 0,
      }).select(),
    ).first;
    return RsMatch.fromJson(row);
  }

  /// Update an existing match.
  Future<RsMatch> updateMatch(
    String matchId,
    Map<String, dynamic> fields,
  ) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_matches')
          .update(fields)
          .eq('id', matchId)
          .select(),
    ).first;
    return RsMatch.fromJson(row);
  }

  /// Delete a match.
  Future<void> deleteMatch(String matchId) async {
    await _client.from('rs_matches').delete().eq('id', matchId);
  }

  /// Toggle match sale status.
  Future<RsMatch> toggleMatchSale(String matchId, {required bool isOnSale}) {
    return updateMatch(matchId, <String, dynamic>{'is_on_sale': isOnSale});
  }

  // ══════════════════════════════════════════════════════════════════════
  // ADMIN — Product CRUD
  // ══════════════════════════════════════════════════════════════════════

  /// Get ALL products (including inactive), for admin listing.
  Future<List<RsProduct>> adminGetAllProducts() async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) return const <RsProduct>[];
    return _asListOfMaps(
      await _client
          .from('rs_shop_products')
          .select()
          .eq('partner_id', partnerId)
          .order('name'),
    ).map(RsProduct.fromJson).toList(growable: false);
  }

  /// Create a new product.
  Future<RsProduct> createProduct({
    required String name,
    required String category,
    required int price,
    required int stock,
    String imageEmoji = '👕',
    bool isActive = true,
    bool isNew = true,
  }) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final row = _asListOfMaps(
      await _client.from('rs_shop_products').insert(<String, dynamic>{
        'partner_id': partnerId,
        'name': name,
        'category': category,
        'price': price,
        'stock': stock,
        'image_emoji': imageEmoji,
        'is_active': isActive,
        'is_new': isNew,
      }).select(),
    ).first;
    return RsProduct.fromJson(row);
  }

  /// Update an existing product.
  Future<RsProduct> updateProduct(
    String productId,
    Map<String, dynamic> fields,
  ) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_shop_products')
          .update(fields)
          .eq('id', productId)
          .select(),
    ).first;
    return RsProduct.fromJson(row);
  }

  /// Delete a product.
  Future<void> deleteProduct(String productId) async {
    await _client.from('rs_shop_products').delete().eq('id', productId);
  }

  /// Toggle product active status.
  Future<RsProduct> toggleProductActive(
    String productId, {
    required bool isActive,
  }) {
    return updateProduct(productId, <String, dynamic>{'is_active': isActive});
  }

  // ══════════════════════════════════════════════════════════════════════
  // ADMIN — Shop Order Management
  // ══════════════════════════════════════════════════════════════════════

  /// Get all shop orders (admin view, across all users).
  Future<List<RsShopOrder>> adminGetAllOrders() async {
    return _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .select()
          .order('created_at', ascending: false),
    ).map(RsShopOrder.fromJson).toList(growable: false);
  }

  /// Update order status (e.g. pending → confirmed → shipped → delivered).
  Future<RsShopOrder> updateOrderStatus(
    String orderId, {
    required String status,
  }) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .update(<String, dynamic>{'status': status})
          .eq('id', orderId)
          .select(),
    ).first;
    return RsShopOrder.fromJson(row);
  }

  // ══════════════════════════════════════════════════════════════════════
  // ADMIN — Ticket Management
  // ══════════════════════════════════════════════════════════════════════

  /// Get all tickets (optionally filtered by match), for admin listing.
  Future<List<RsTicket>> adminGetAllTickets({String? matchId}) async {
    var query = _client.from('rs_tickets').select('*, rs_matches(*)');
    if (matchId != null && matchId.isNotEmpty) {
      query = query.eq('match_id', matchId);
    }
    final rows = _asListOfMaps(
      await query.order('purchased_at', ascending: false),
    );
    return rows.map(RsTicket.fromJson).toList(growable: false);
  }

  /// Update a ticket's status (e.g. pending → valid → used).
  Future<void> updateTicketStatus(
    String ticketId, {
    required String status,
  }) async {
    await _client
        .from('rs_tickets')
        .update(<String, dynamic>{'status': status})
        .eq('id', ticketId);
  }

  /// Get ticket stats for a match (total sold, revenue, status breakdown).
  Future<Map<String, dynamic>> getMatchTicketStats(String matchId) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_tickets')
          .select('status, seat_type, amount_paid')
          .eq('match_id', matchId),
    );
    var totalSold = 0;
    var totalRevenue = 0;
    var generalCount = 0;
    var vipCount = 0;
    final statusCounts = <String, int>{};
    for (final row in rows) {
      totalSold++;
      totalRevenue += (row['amount_paid'] as num?)?.toInt() ?? 0;
      final seatType = (row['seat_type']?.toString() ?? '').toLowerCase();
      if (seatType == 'vip') {
        vipCount++;
      } else {
        generalCount++;
      }
      final status = row['status']?.toString() ?? 'pending';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }
    return <String, dynamic>{
      'total_sold': totalSold,
      'total_revenue': totalRevenue,
      'general_count': generalCount,
      'vip_count': vipCount,
      'status_counts': statusCounts,
    };
  }

  // ══════════════════════════════════════════════════════════════════════
  // ADMIN — Fan Club CRUD
  // ══════════════════════════════════════════════════════════════════════

  /// Get all fan clubs for admin (no region filter).
  Future<List<RsFanClub>> adminGetAllFanClubs() async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) return const <RsFanClub>[];
    return _asListOfMaps(
      await _client
          .from('rs_fan_clubs')
          .select()
          .eq('partner_id', partnerId)
          .order('name'),
    ).map(RsFanClub.fromJson).toList(growable: false);
  }

  /// Create a fan club.
  Future<RsFanClub> createFanClub({
    required String name,
    required String region,
    required String description,
    String bannerEmoji = '🥁',
  }) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final row = _asListOfMaps(
      await _client.from('rs_fan_clubs').insert(<String, dynamic>{
        'partner_id': partnerId,
        'name': name,
        'region': region,
        'description': description,
        'banner_emoji': bannerEmoji,
        'member_count': 0,
        'event_count': 0,
        'rating': 0,
      }).select(),
    ).first;
    return RsFanClub.fromJson(row);
  }

  /// Update a fan club.
  Future<RsFanClub> updateFanClub(
    String clubId,
    Map<String, dynamic> fields,
  ) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_fan_clubs')
          .update(fields)
          .eq('id', clubId)
          .select(),
    ).first;
    return RsFanClub.fromJson(row);
  }

  /// Delete a fan club.
  Future<void> deleteFanClub(String clubId) async {
    await _client.from('rs_fan_clubs').delete().eq('id', clubId);
  }

  // ══════════════════════════════════════════════════════════════════════
  // ADMIN — Initiative CRUD
  // ══════════════════════════════════════════════════════════════════════

  /// Get ALL initiatives (including inactive), for admin.
  Future<List<RsInitiative>> adminGetAllInitiatives() async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) return const <RsInitiative>[];
    return _asListOfMaps(
      await _client
          .from('rs_initiatives')
          .select()
          .eq('partner_id', partnerId)
          .order('ends_at', ascending: false),
    ).map(RsInitiative.fromJson).toList(growable: false);
  }

  /// Create an initiative.
  Future<RsInitiative> createInitiative({
    required String title,
    required String description,
    required String category,
    required int targetAmount,
    required DateTime endsAt,
    bool isActive = true,
  }) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final row = _asListOfMaps(
      await _client.from('rs_initiatives').insert(<String, dynamic>{
        'partner_id': partnerId,
        'title': title,
        'description': description,
        'category': category,
        'target_amount': targetAmount,
        'raised_amount': 0,
        'supporter_count': 0,
        'is_active': isActive,
        'ends_at': endsAt.toIso8601String(),
      }).select(),
    ).first;
    return RsInitiative.fromJson(row);
  }

  /// Update an initiative.
  Future<RsInitiative> updateInitiative(
    String initiativeId,
    Map<String, dynamic> fields,
  ) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_initiatives')
          .update(fields)
          .eq('id', initiativeId)
          .select(),
    ).first;
    return RsInitiative.fromJson(row);
  }

  /// Toggle initiative active status.
  Future<RsInitiative> toggleInitiativeActive(
    String initiativeId, {
    required bool isActive,
  }) {
    return updateInitiative(initiativeId, <String, dynamic>{
      'is_active': isActive,
    });
  }

  // ══════════════════════════════════════════════════════════════════════
  // ADMIN — Membership Management
  // ══════════════════════════════════════════════════════════════════════

  /// Get all memberships for admin view.
  Future<List<FanMembership>> adminGetAllMembers() async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) return const <FanMembership>[];

    final rows = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .select()
          .eq('partner_id', partnerId)
          .order('points', ascending: false),
    );

    if (rows.isEmpty) return const <FanMembership>[];

    return rows
        .map((row) => FanMembership.fromJson(_withResolvedDisplayName(row)))
        .toList(growable: false);
  }

  /// Update a member's tier manually.
  Future<FanMembership> updateMemberTier(String userId, String tier) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final row = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, dynamic>{
            'tier': tier,
            'display_name': _displayNameForUser(userId),
          })
          .eq('partner_id', partnerId)
          .eq('user_id', userId)
          .select(),
    ).first;
    return FanMembership.fromJson(_withResolvedDisplayName(row));
  }

  /// Set a member's points to an absolute value.
  Future<FanMembership> setMemberPoints(String userId, int points) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final newTier = FanTierX.fromPoints(points);
    final row = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, dynamic>{
            'points': points,
            'tier': newTier.name,
            'display_name': _displayNameForUser(userId),
          })
          .eq('partner_id', partnerId)
          .eq('user_id', userId)
          .select(),
    ).first;
    return FanMembership.fromJson(_withResolvedDisplayName(row));
  }

  Map<String, dynamic> _withResolvedDisplayName(Map<String, dynamic> row) {
    final userId = row['user_id']?.toString();
    return <String, dynamic>{
      ...row,
      'display_name': _displayNameForUser(
        userId,
        seededDisplayName: row['display_name']?.toString(),
      ),
    };
  }

  String _displayNameForUser(
    String? userId, {
    String? seededDisplayName,
    String fallback = '000000',
  }) {
    final currentUser = _client.auth.currentUser;
    final currentMetadata =
        currentUser?.userMetadata ?? const <String, dynamic>{};

    if (userId != null && currentUser?.id == userId) {
      return PublicUserIdentity.resolve(
        publicUserId:
            currentMetadata['public_user_id']?.toString() ?? seededDisplayName,
        userId: userId,
        phone: currentUser?.phone,
        fallback: fallback,
      );
    }

    return PublicUserIdentity.resolve(
      publicUserId: seededDisplayName,
      userId: userId,
      fallback: fallback,
    );
  }

  String _supporterNameForRow(Map<String, dynamic> row) {
    final seededName = row['supporter_name']?.toString();
    final userId = row['user_id']?.toString();
    return _displayNameForUser(
      userId,
      seededDisplayName: seededName,
      fallback: 'Supporter',
    );
  }
}

List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((row) => row.map((key, val) => MapEntry('$key', val)))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry('$key', val));
  }
  return const <String, dynamic>{};
}

Map<String, dynamic>? _asMapOrNull(dynamic value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry('$key', val));
  }
  return null;
}

String? _nullIfBlank(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
