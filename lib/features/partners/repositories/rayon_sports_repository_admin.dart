part of 'rayon_sports_repository.dart';

extension RayonSportsAdminRepository on RayonSportsRepository {
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
      await _client.from('rs_matches').insert(<String, Object?>{
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

  Future<RsMatch> updateMatch(String matchId, RsJsonMap fields) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_matches')
          .update(fields)
          .eq('id', matchId)
          .select(),
    ).first;
    return RsMatch.fromJson(row);
  }

  Future<void> deleteMatch(String matchId) async {
    await _client.from('rs_matches').delete().eq('id', matchId);
  }

  Future<RsMatch> toggleMatchSale(String matchId, {required bool isOnSale}) {
    return updateMatch(matchId, <String, Object?>{'is_on_sale': isOnSale});
  }

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
      await _client.from('rs_shop_products').insert(<String, Object?>{
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

  Future<RsProduct> updateProduct(String productId, RsJsonMap fields) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_shop_products')
          .update(fields)
          .eq('id', productId)
          .select(),
    ).first;
    return RsProduct.fromJson(row);
  }

  Future<void> deleteProduct(String productId) async {
    await _client.from('rs_shop_products').delete().eq('id', productId);
  }

  Future<RsProduct> toggleProductActive(
    String productId, {
    required bool isActive,
  }) {
    return updateProduct(productId, <String, Object?>{'is_active': isActive});
  }

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
    final row = _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .update(<String, Object?>{'status': status})
          .eq('id', orderId)
          .select(),
    ).first;
    return RsShopOrder.fromJson(row);
  }

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
    return <String, Object?>{
      'total_sold': totalSold,
      'total_revenue': totalRevenue,
      'general_count': generalCount,
      'vip_count': vipCount,
      'status_counts': statusCounts,
    };
  }

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

  Future<RsFanClub> createFanClub({
    required String name,
    required String region,
    required String description,
    String bannerEmoji = '🥁',
  }) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final row = _asListOfMaps(
      await _client.from('rs_fan_clubs').insert(<String, Object?>{
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

  Future<RsFanClub> updateFanClub(String clubId, RsJsonMap fields) async {
    final row = _asListOfMaps(
      await _client
          .from('rs_fan_clubs')
          .update(fields)
          .eq('id', clubId)
          .select(),
    ).first;
    return RsFanClub.fromJson(row);
  }

  Future<void> deleteFanClub(String clubId) async {
    await _client.from('rs_fan_clubs').delete().eq('id', clubId);
  }

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
      await _client.from('rs_initiatives').insert(<String, Object?>{
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

  Future<RsInitiative> updateInitiative(
    String initiativeId,
    RsJsonMap fields,
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

  Future<RsInitiative> toggleInitiativeActive(
    String initiativeId, {
    required bool isActive,
  }) {
    return updateInitiative(initiativeId, <String, Object?>{
      'is_active': isActive,
    });
  }

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

  Future<FanMembership> updateMemberTier(String userId, String tier) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final row = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, Object?>{
            'tier': tier,
            'display_name': _displayNameForUser(userId),
          })
          .eq('partner_id', partnerId)
          .eq('user_id', userId)
          .select(),
    ).first;
    return FanMembership.fromJson(_withResolvedDisplayName(row));
  }

  Future<FanMembership> setMemberPoints(String userId, int points) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) throw StateError('Rayon Sports partner not found.');
    final newTier = FanTierX.fromPoints(points);
    final row = _asListOfMaps(
      await _client
          .from('rs_fan_memberships')
          .update(<String, Object?>{
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

  Future<List<PartnerPaymentRoute>> adminGetPaymentRoutes() async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) {
      return const <PartnerPaymentRoute>[];
    }

    final rows = _asListOfMaps(
      await _client
          .from('partner_payment_routes')
          .select('*, partners(name, slug)')
          .eq('partner_id', partnerId)
          .order('country')
          .order('updated_at', ascending: false),
    );
    return rows
        .map((row) {
          final partner = _asMap(row['partners']);
          return PartnerPaymentRoute.fromJson(<String, Object?>{
            ...row,
            'partner_name': partner['name'],
            'partner_slug': partner['slug'],
          });
        })
        .toList(growable: false);
  }

  Future<PartnerPaymentRoute> upsertPaymentRoute({
    required String countryCode,
    required String providerId,
    required String recipientCode,
    required String reconciliationLabel,
    required PartnerPaymentRouteStatus status,
  }) async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) {
      throw StateError('Rayon Sports partner not found.');
    }

    final row = _asListOfMaps(
      await _client
          .from('partner_payment_routes')
          .upsert(<String, Object?>{
            'partner_id': partnerId,
            'country': countryCode,
            'provider': providerId,
            'recipient_code': recipientCode,
            'reconciliation_label': reconciliationLabel,
            'status': status.name,
          }, onConflict: 'partner_id,country')
          .select('*, partners(name, slug)'),
    ).first;
    final partner = _asMap(row['partners']);
    return PartnerPaymentRoute.fromJson(<String, Object?>{
      ...row,
      'partner_name': partner['name'],
      'partner_slug': partner['slug'],
    });
  }

  Future<void> deletePaymentRoute(String routeId) async {
    await _client.from('partner_payment_routes').delete().eq('id', routeId);
  }

  Future<List<RsMembershipPackage>> adminGetMembershipPackages() async {
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) {
      return RsMembershipPackage.fallback();
    }

    final rows = _asListOfMaps(
      await _client
          .from('rs_membership_packages')
          .select()
          .eq('partner_id', partnerId)
          .order('sort_order')
          .order('tier'),
    );
    if (rows.isEmpty) {
      return RsMembershipPackage.fallback();
    }
    return rows.map(RsMembershipPackage.fromJson).toList(growable: false);
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
    final partnerId = await _resolvePartnerId();
    if (partnerId == null) {
      throw StateError('Rayon Sports partner not found.');
    }

    final row = _asListOfMaps(
      await _client.from('rs_membership_packages').upsert(<String, Object?>{
        'partner_id': partnerId,
        'tier': tier.name,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'benefits': benefits.map((benefit) => benefit.toJson()).toList(),
        'is_active': isActive,
        'sort_order': sortOrder,
      }, onConflict: 'partner_id,tier').select(),
    ).first;
    return RsMembershipPackage.fromJson(row);
  }
}
