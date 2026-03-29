part of 'rayon_sports_repository.dart';

/// Admin-only CRUD operations on Rayon Sports data.
///
/// This is structured as a helper class instantiated from the main
/// [RayonSportsRepository] so admin call-sites are explicit (`RayonSportsAdminRepository(this).adminGetAllMatches()`).
class RayonSportsAdminRepository {
  RayonSportsAdminRepository(this._repo);

  final RayonSportsRepository _repo;
  SupabaseClient get _client => _repo._client;

  // ─── Matches ───────────────────────────────────────────────────────

  Future<List<RsMatch>> adminGetAllMatches() async {
    return _asListOfMaps(
      await _client.from('rs_matches').select().order('match_date'),
    ).map(RsMatch.fromJson).toList(growable: false);
  }

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
    final partnerId = await _repo._resolvePartnerId();
    final rows = _asListOfMaps(
      await _client
          .from('rs_matches')
          .insert(<String, Object?>{
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
          })
          .select(),
    );
    return RsMatch.fromJson(rows.first);
  }

  Future<RsMatch> updateMatch(String matchId, RsJsonMap fields) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_matches')
          .update(fields)
          .eq('id', matchId)
          .select(),
    );
    return RsMatch.fromJson(rows.first);
  }

  Future<void> deleteMatch(String matchId) async {
    await _client.from('rs_matches').delete().eq('id', matchId);
  }

  Future<RsMatch> toggleMatchSale(
    String matchId, {
    required bool isOnSale,
  }) async {
    return updateMatch(matchId, <String, Object?>{'is_on_sale': isOnSale});
  }

  // ─── Products ──────────────────────────────────────────────────────

  Future<List<RsProduct>> adminGetAllProducts() async {
    return _asListOfMaps(
      await _client.from('rs_products').select().order('created_at'),
    ).map(RsProduct.fromJson).toList(growable: false);
  }

  Future<RsProduct> createProduct({
    required String name,
    required String category,
    required int price,
    required int stock,
    String imageEmoji = '👕',
    bool isActive = true,
    bool isNew = true,
  }) async {
    final partnerId = await _repo._resolvePartnerId();
    final rows = _asListOfMaps(
      await _client
          .from('rs_products')
          .insert(<String, Object?>{
            'partner_id': partnerId,
            'name': name,
            'category': category,
            'price': price,
            'stock': stock,
            'image_emoji': imageEmoji,
            'is_active': isActive,
            'is_new': isNew,
          })
          .select(),
    );
    return RsProduct.fromJson(rows.first);
  }

  Future<RsProduct> updateProduct(String productId, RsJsonMap fields) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_products')
          .update(fields)
          .eq('id', productId)
          .select(),
    );
    return RsProduct.fromJson(rows.first);
  }

  Future<void> deleteProduct(String productId) async {
    await _client.from('rs_products').delete().eq('id', productId);
  }

  Future<RsProduct> toggleProductActive(
    String productId, {
    required bool isActive,
  }) async {
    return updateProduct(productId, <String, Object?>{'is_active': isActive});
  }

  Future<RsProduct> adminAdjustStock(String productId, int delta) async {
    final current = _asListOfMaps(
      await _client.from('rs_products').select('stock').eq('id', productId),
    ).first;
    final newStock = ((current['stock'] as num?)?.toInt() ?? 0) + delta;
    return updateProduct(
      productId,
      <String, Object?>{'stock': newStock < 0 ? 0 : newStock},
    );
  }

  // ─── Orders ────────────────────────────────────────────────────────

  Future<List<RsShopOrder>> adminGetAllOrders() async {
    return _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .select()
          .order('created_at', ascending: false),
    ).map(RsShopOrder.fromJson).toList(growable: false);
  }

  Future<RsShopOrder> updateOrderStatus(
    String orderId, {
    required String status,
  }) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .update(<String, Object?>{'status': status})
          .eq('id', orderId)
          .select(),
    );
    return RsShopOrder.fromJson(rows.first);
  }

  // ─── Tickets ───────────────────────────────────────────────────────

  Future<List<RsTicket>> adminGetAllTickets({String? matchId}) async {
    var query = _client.from('rs_tickets').select('*, rs_matches(*)');
    if (matchId != null && matchId.trim().isNotEmpty) {
      query = query.eq('match_id', matchId);
    }
    return _asListOfMaps(
      await query.order('purchased_at', ascending: false),
    ).map(RsTicket.fromJson).toList(growable: false);
  }

  Future<void> updateTicketStatus(
    String ticketId, {
    required String status,
  }) async {
    await _client
        .from('rs_tickets')
        .update(<String, Object?>{'status': status})
        .eq('id', ticketId);
  }

  Future<RsJsonMap> getMatchTicketStats(String matchId) async {
    final result = await _client.rpc(
      'get_rs_match_ticket_stats',
      params: <String, Object?>{'p_match_id': matchId},
    );
    return _asMap(result);
  }

  // ─── Fan Clubs ─────────────────────────────────────────────────────

  Future<List<RsFanClub>> adminGetAllFanClubs() async {
    return _asListOfMaps(
      await _client.from('rs_fan_clubs').select().order('name'),
    ).map(RsFanClub.fromJson).toList(growable: false);
  }

  // ─── Initiatives ───────────────────────────────────────────────────

  Future<List<RsInitiative>> adminGetAllInitiatives() async {
    return _asListOfMaps(
      await _client.from('rs_initiatives').select().order('created_at'),
    ).map(RsInitiative.fromJson).toList(growable: false);
  }

  Future<RsInitiative> createInitiative({
    required String title,
    required String description,
    required String category,
    required int targetAmount,
    required DateTime endsAt,
    bool isActive = true,
  }) async {
    final partnerId = await _repo._resolvePartnerId();
    final rows = _asListOfMaps(
      await _client
          .from('rs_initiatives')
          .insert(<String, Object?>{
            'partner_id': partnerId,
            'title': title,
            'description': description,
            'category': category,
            'target_amount': targetAmount,
            'ends_at': endsAt.toIso8601String(),
            'is_active': isActive,
          })
          .select(),
    );
    return RsInitiative.fromJson(rows.first);
  }

  Future<RsInitiative> updateInitiative(
    String initiativeId,
    RsJsonMap fields,
  ) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_initiatives')
          .update(fields)
          .eq('id', initiativeId)
          .select(),
    );
    return RsInitiative.fromJson(rows.first);
  }

  Future<RsInitiative> toggleInitiativeActive(
    String initiativeId, {
    required bool isActive,
  }) async {
    return updateInitiative(
      initiativeId,
      <String, Object?>{'is_active': isActive},
    );
  }

  Future<void> deleteInitiative(String initiativeId) async {
    await _client.from('rs_initiatives').delete().eq('id', initiativeId);
  }

  // ─── Members ───────────────────────────────────────────────────────

  Future<List<FanMembership>> adminGetAllMembers() async {
    return _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .select()
          .order('points', ascending: false),
    ).map(FanMembership.fromJson).toList(growable: false);
  }

  Future<FanMembership> updateMemberTier(String userId, String tier) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, Object?>{'tier': tier})
          .eq('user_id', userId)
          .select(),
    );
    return FanMembership.fromJson(rows.first);
  }

  Future<FanMembership> setMemberPoints(String userId, int points) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, Object?>{'points': points})
          .eq('user_id', userId)
          .select(),
    );
    return FanMembership.fromJson(rows.first);
  }

  Future<FanMembership> renewMembership(
    String userId,
    DateTime newExpiry,
  ) async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, Object?>{
            'expires_at': newExpiry.toIso8601String(),
            'status': 'active',
          })
          .eq('user_id', userId)
          .select(),
    );
    return FanMembership.fromJson(rows.first);
  }

  // ─── Payment Routes ────────────────────────────────────────────────

  Future<List<PartnerPaymentRoute>> adminGetPaymentRoutes() async {
    final rows = _asListOfMaps(
      await _client
          .from('partner_payment_routes')
          .select()
          .order('created_at'),
    );
    return rows
        .map(PartnerPaymentRoute.fromJson)
        .toList(growable: false);
  }

  Future<PartnerPaymentRoute> upsertPaymentRoute({
    required String countryCode,
    required String providerId,
    required String recipientCode,
    required String reconciliationLabel,
    required PartnerPaymentRouteStatus status,
  }) async {
    final partnerId = await _repo._resolvePartnerId();
    final rows = _asListOfMaps(
      await _client
          .from('partner_payment_routes')
          .upsert(<String, Object?>{
            'partner_id': partnerId,
            'country_code': countryCode,
            'provider_id': providerId,
            'recipient_code': recipientCode,
            'reconciliation_label': reconciliationLabel,
            'status': status.name,
          })
          .select(),
    );
    return PartnerPaymentRoute.fromJson(rows.first);
  }

  Future<void> deletePaymentRoute(String routeId) async {
    await _client.from('partner_payment_routes').delete().eq('id', routeId);
  }

  // ─── Membership Packages ──────────────────────────────────────────

  Future<List<RsMembershipPackage>> adminGetMembershipPackages() async {
    final rows = _asListOfMaps(
      await _client
          .from('rs_membership_packages')
          .select()
          .order('sort_order'),
    );
    return rows
        .map(RsMembershipPackage.fromJson)
        .toList(growable: false);
  }

  Future<RsMembershipPackage> upsertMembershipPackage({
    required FanTier tier,
    required String title,
    required String subtitle,
    required String description,
    required List<RsMembershipPackageBenefit> benefits,
    required bool isActive,
    required int sortOrder,
  }) async {
    final partnerId = await _repo._resolvePartnerId();
    final rows = _asListOfMaps(
      await _client
          .from('rs_membership_packages')
          .upsert(<String, Object?>{
            'partner_id': partnerId,
            'tier': tier.name,
            'title': title,
            'subtitle': subtitle,
            'description': description,
            'benefits': benefits.map((b) => b.toJson()).toList(),
            'is_active': isActive,
            'sort_order': sortOrder,
          })
          .select(),
    );
    return RsMembershipPackage.fromJson(rows.first);
  }
}
