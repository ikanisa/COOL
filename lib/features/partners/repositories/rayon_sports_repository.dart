import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/identity/public_user_identity.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/services/operational_health_service.dart';
import '../../../core/services/hive_runtime.dart';
import '../rayon/models/rs_models.dart';
import '../rayon/rs_membership_package.dart';
import '../rayon/rayon_payment.dart';
import '../rayon/rayon_ticket_qr.dart';
import 'rayon_sports_checkout.dart';
import 'rayon_sports_repository_dashboard.dart';
import 'rayon_sports_repository_membership.dart';

part 'rayon_sports_repository_admin.dart';
part 'rayon_sports_repository_initiatives.dart';
part 'rayon_sports_repository_shop.dart';
part 'rayon_sports_repository_tickets.dart';

class RayonSportsRepository {
  RayonSportsRepository({
    required SupabaseClient client,
    required OpenHiveBox<dynamic> openBox,
    MomoService? momoService,
    OperationalHealthService? operationalHealthService,
  }) : _client = client,
       _momoService =
           momoService ?? MomoService(client: client, openBox: openBox),
       _operationalHealthService =
           operationalHealthService ??
           OperationalHealthService(client: client) {
    _membershipRepository = RayonSportsMembershipRepository(
      client: _client,
      displayNameForUser: _displayNameForUser,
      withResolvedDisplayName: _withResolvedDisplayName,
    );
    _dashboardRepository = RayonSportsDashboardRepository(
      client: _client,
      resolvePartnerId: _membershipRepository.resolvePartnerId,
      withResolvedDisplayName: _withResolvedDisplayName,
    );
    _checkoutService = RayonSportsCheckoutService(
      momoService: _momoService,
      operationalHealthService: _operationalHealthService,
      getActivePaymentRoute: _membershipRepository.getActivePaymentRoute,
    );
  }

  final SupabaseClient _client;
  final MomoService _momoService;
  final OperationalHealthService _operationalHealthService;
  late final RayonSportsCheckoutService _checkoutService;
  late final RayonSportsDashboardRepository _dashboardRepository;
  late final RayonSportsMembershipRepository _membershipRepository;

  Future<String?> _resolvePartnerId() =>
      _membershipRepository.resolvePartnerId();

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

  RsJsonMap _withResolvedDisplayName(RsJsonMap row) {
    final userId = row['user_id']?.toString();
    return <String, Object?>{
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
    final currentMetadata = _asMap(currentUser?.userMetadata);

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

  String _supporterNameForRow(RsJsonMap row) {
    final seededName = row['supporter_name']?.toString();
    final userId = row['user_id']?.toString();
    return _displayNameForUser(
      userId,
      seededDisplayName: seededName,
      fallback: 'Supporter',
    );
  }

  // Admin adapters keep call sites stable while admin operations live in a
  // dedicated extension part.
  Future<List<RsMatch>> adminGetAllMatches() =>
      RayonSportsAdminRepository(this).adminGetAllMatches();

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
  }) {
    return RayonSportsAdminRepository(this).createMatch(
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      competition: competition,
      venue: venue,
      matchDate: matchDate,
      kickoffTime: kickoffTime,
      ticketGeneralPrice: ticketGeneralPrice,
      ticketVipPrice: ticketVipPrice,
      capacity: capacity,
      saleStartsAt: saleStartsAt,
      isOnSale: isOnSale,
    );
  }

  Future<RsMatch> updateMatch(String matchId, RsJsonMap fields) {
    return RayonSportsAdminRepository(this).updateMatch(matchId, fields);
  }

  Future<void> deleteMatch(String matchId) =>
      RayonSportsAdminRepository(this).deleteMatch(matchId);

  Future<RsMatch> toggleMatchSale(String matchId, {required bool isOnSale}) {
    return RayonSportsAdminRepository(
      this,
    ).toggleMatchSale(matchId, isOnSale: isOnSale);
  }

  Future<List<RsProduct>> adminGetAllProducts() =>
      RayonSportsAdminRepository(this).adminGetAllProducts();

  Future<RsProduct> createProduct({
    required String name,
    required String category,
    required int price,
    required int stock,
    String imageEmoji = '👕',
    bool isActive = true,
    bool isNew = true,
  }) {
    return RayonSportsAdminRepository(this).createProduct(
      name: name,
      category: category,
      price: price,
      stock: stock,
      imageEmoji: imageEmoji,
      isActive: isActive,
      isNew: isNew,
    );
  }

  Future<RsProduct> updateProduct(String productId, RsJsonMap fields) {
    return RayonSportsAdminRepository(this).updateProduct(productId, fields);
  }

  Future<void> deleteProduct(String productId) =>
      RayonSportsAdminRepository(this).deleteProduct(productId);

  Future<RsProduct> toggleProductActive(
    String productId, {
    required bool isActive,
  }) {
    return RayonSportsAdminRepository(
      this,
    ).toggleProductActive(productId, isActive: isActive);
  }

  Future<List<RsShopOrder>> adminGetAllOrders() =>
      RayonSportsAdminRepository(this).adminGetAllOrders();

  Future<RsShopOrder> updateOrderStatus(
    String orderId, {
    required String status,
  }) {
    return RayonSportsAdminRepository(
      this,
    ).updateOrderStatus(orderId, status: status);
  }

  Future<List<RsTicket>> adminGetAllTickets({String? matchId}) {
    return RayonSportsAdminRepository(
      this,
    ).adminGetAllTickets(matchId: matchId);
  }

  Future<void> updateTicketStatus(String ticketId, {required String status}) {
    return RayonSportsAdminRepository(
      this,
    ).updateTicketStatus(ticketId, status: status);
  }

  Future<RsJsonMap> getMatchTicketStats(String matchId) {
    return RayonSportsAdminRepository(this).getMatchTicketStats(matchId);
  }

  Future<List<RsFanClub>> adminGetAllFanClubs() =>
      RayonSportsAdminRepository(this).adminGetAllFanClubs();

  Future<List<RsInitiative>> adminGetAllInitiatives() =>
      RayonSportsAdminRepository(this).adminGetAllInitiatives();

  Future<RsInitiative> createInitiative({
    required String title,
    required String description,
    required String category,
    required int targetAmount,
    required DateTime endsAt,
    bool isActive = true,
  }) {
    return RayonSportsAdminRepository(this).createInitiative(
      title: title,
      description: description,
      category: category,
      targetAmount: targetAmount,
      endsAt: endsAt,
      isActive: isActive,
    );
  }

  Future<RsInitiative> updateInitiative(String initiativeId, RsJsonMap fields) {
    return RayonSportsAdminRepository(
      this,
    ).updateInitiative(initiativeId, fields);
  }

  Future<RsInitiative> toggleInitiativeActive(
    String initiativeId, {
    required bool isActive,
  }) {
    return RayonSportsAdminRepository(
      this,
    ).toggleInitiativeActive(initiativeId, isActive: isActive);
  }

  Future<List<FanMembership>> adminGetAllMembers() =>
      RayonSportsAdminRepository(this).adminGetAllMembers();

  Future<FanMembership> updateMemberTier(String userId, String tier) {
    return RayonSportsAdminRepository(this).updateMemberTier(userId, tier);
  }

  Future<FanMembership> setMemberPoints(String userId, int points) {
    return RayonSportsAdminRepository(this).setMemberPoints(userId, points);
  }

  Future<List<PartnerPaymentRoute>> adminGetPaymentRoutes() =>
      RayonSportsAdminRepository(this).adminGetPaymentRoutes();

  Future<PartnerPaymentRoute> upsertPaymentRoute({
    required String countryCode,
    required String providerId,
    required String recipientCode,
    required String reconciliationLabel,
    required PartnerPaymentRouteStatus status,
  }) {
    return RayonSportsAdminRepository(this).upsertPaymentRoute(
      countryCode: countryCode,
      providerId: providerId,
      recipientCode: recipientCode,
      reconciliationLabel: reconciliationLabel,
      status: status,
    );
  }

  Future<void> deletePaymentRoute(String routeId) =>
      RayonSportsAdminRepository(this).deletePaymentRoute(routeId);

  Future<List<RsMembershipPackage>> adminGetMembershipPackages() =>
      RayonSportsAdminRepository(this).adminGetMembershipPackages();

  Future<RsMembershipPackage> upsertMembershipPackage({
    required FanTier tier,
    required String title,
    required String subtitle,
    required String description,
    required List<RsMembershipPackageBenefit> benefits,
    required bool isActive,
    required int sortOrder,
  }) {
    return RayonSportsAdminRepository(this).upsertMembershipPackage(
      tier: tier,
      title: title,
      subtitle: subtitle,
      description: description,
      benefits: benefits,
      isActive: isActive,
      sortOrder: sortOrder,
    );
  }

  // Public instance wrappers keep the repository mockable in tests even though
  // most implementation currently lives in extension parts.
  Future<RayonSportsData> loadData({String? userId}) =>
      _dashboardRepository.loadData(userId: userId);

  Future<void> joinClub({required String clubId, required String userId}) =>
      _membershipRepository.joinClub(clubId: clubId, userId: userId);

  Future<void> leaveClub({required String clubId, required String userId}) =>
      _membershipRepository.leaveClub(clubId: clubId, userId: userId);

  Future<List<RsFanClub>> getUserClubs(String userId) =>
      _membershipRepository.getUserClubs(userId);

  Future<String?> getRayonPartnerId() =>
      _membershipRepository.getRayonPartnerId();

  Future<PartnerPaymentRoute> getActivePaymentRoute({
    bool forceRefresh = false,
  }) => _membershipRepository.getActivePaymentRoute(forceRefresh: forceRefresh);

  Future<List<RsMembershipPackage>> getMembershipPackages({
    String? partnerId,
    bool includeInactive = false,
  }) => _membershipRepository.getMembershipPackages(
    partnerId: partnerId,
    includeInactive: includeInactive,
  );

  Future<bool> isGoogleWalletOperationallyReady() =>
      _membershipRepository.isGoogleWalletOperationallyReady();

  Future<RsFanMembership?> getRayonFanMembership(String userId) =>
      _membershipRepository.getRayonFanMembership(userId);

  Future<RsFanMembership?> getFanMembership(String userId, String partnerId) =>
      _membershipRepository.getFanMembership(userId, partnerId);

  Future<List<RsAchievement>> getAchievements({
    required String userId,
    required String partnerId,
  }) => _membershipRepository.getAchievements(
    userId: userId,
    partnerId: partnerId,
  );

  Future<RsFanMembership> createFanMembership(
    String userId, {
    String? partnerId,
  }) => _membershipRepository.createFanMembership(userId, partnerId: partnerId);

  Future<RsFanMembership> addPoints(
    String userId,
    String partnerId,
    int points,
    String reason,
  ) => _membershipRepository.addPoints(userId, partnerId, points, reason);

  Future<List<RsRegistryMember>> getMembers(
    String partnerId, {
    String? searchQuery,
    FanTier? filterTier,
    String? region,
    int limit = 20,
    int offset = 0,
  }) => _membershipRepository.getMembers(
    partnerId,
    searchQuery: searchQuery,
    filterTier: filterTier,
    region: region,
    limit: limit,
    offset: offset,
  );

  Future<List<RsFanClub>> getFanClubs(String partnerId, String? region) =>
      _membershipRepository.getFanClubs(partnerId, region);

  Future<List<RsShopProduct>> getProducts(String partnerId, String? category) =>
      RayonSportsShopRepository(this).getProducts(partnerId, category);

  Future<String> placeOrder({
    required String userId,
    required List<RsShopProduct> products,
    required Map<String, int> quantities,
    required String deliveryAddress,
    String? referralInviteId,
    int discountAmount = 0,
  }) => RayonSportsShopRepository(this).placeOrder(
    userId: userId,
    products: products,
    quantities: quantities,
    deliveryAddress: deliveryAddress,
    referralInviteId: referralInviteId,
    discountAmount: discountAmount,
  );

  Future<List<Map<String, dynamic>>> getMyOrders(String userId) =>
      RayonSportsShopRepository(this).getMyOrders(userId);

  Future<List<RsShopOrder>> getMyShopOrders(String userId) =>
      RayonSportsShopRepository(this).getMyShopOrders(userId);

  Future<void> cancelOrder(String orderId) =>
      RayonSportsShopRepository(this).cancelOrder(orderId);

  Future<List<RsMatch>> getMatches(String partnerId, bool onSaleOnly) =>
      RayonSportsTicketRepository(this).getMatches(partnerId, onSaleOnly);

  Future<List<RsTicket>> purchaseTickets({
    required String matchId,
    required String userId,
    required String seatType,
    required int quantity,
    String? referralInviteId,
  }) => RayonSportsTicketRepository(this).purchaseTickets(
    matchId: matchId,
    userId: userId,
    seatType: seatType,
    quantity: quantity,
    referralInviteId: referralInviteId,
  );

  Future<List<RsTicket>> getMyTickets(String userId) =>
      RayonSportsTicketRepository(this).getMyTickets(userId);

  Future<void> cancelTicket(String ticketId) =>
      RayonSportsTicketRepository(this).cancelTicket(ticketId);

  Future<String> createGoogleWalletSaveUrl({required String ticketId}) =>
      RayonSportsTicketRepository(
        this,
      ).createGoogleWalletSaveUrl(ticketId: ticketId);

  Future<String> supportInitiative({
    required String userId,
    required String initiativeId,
    required int amount,
    String? referralInviteId,
  }) => RayonSportsInitiativeRepository(this).supportInitiative(
    userId: userId,
    initiativeId: initiativeId,
    amount: amount,
    referralInviteId: referralInviteId,
  );

  Future<List<RsInitiative>> getInitiatives(String partnerId) =>
      RayonSportsInitiativeRepository(this).getInitiatives(partnerId);

  Future<String> contribute({
    required String initiativeId,
    required String userId,
    required int amount,
    String? referralInviteId,
  }) => RayonSportsInitiativeRepository(this).contribute(
    initiativeId: initiativeId,
    userId: userId,
    amount: amount,
    referralInviteId: referralInviteId,
  );

  Future<List<RsJsonMap>> getRecentContributors(
    String initiativeId,
    int limit,
  ) => RayonSportsInitiativeRepository(
    this,
  ).getRecentContributors(initiativeId, limit);

  Future<List<RsInitiativeContribution>> getRecentContributionActivity(
    String initiativeId,
    int limit,
  ) => RayonSportsInitiativeRepository(
    this,
  ).getRecentContributionActivity(initiativeId, limit);

  // ═══════════════════════════════════════════════════════════════
  // Phase 4: Notifications, Analytics, Batch Ticket Ops
  // ═══════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchRsFanAnalytics() async {
    final result = await _client.rpc('get_rs_fan_analytics');
    if (result is Map<String, dynamic>) return result;
    return const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> fetchRsNotifications({
    String? matchId,
  }) async {
    final result = await _client.rpc('get_rs_notifications', params: {
      'p_match_id': matchId,
    });
    return _asListOfMaps(result);
  }

  Future<String> sendMatchNotification({
    required String matchId,
    required String title,
    required String body,
  }) async {
    final result = await _client.rpc('send_rs_match_notification', params: {
      'p_match_id': matchId,
      'p_title': title,
      'p_body': body,
    });
    return result.toString();
  }

  Future<int> bulkVoidTickets(List<String> ticketIds) async {
    final result = await _client.rpc('bulk_void_rs_tickets', params: {
      'p_ticket_ids': ticketIds,
    });
    return (result as num?)?.toInt() ?? 0;
  }

  Future<int> bulkRefundTickets(List<String> ticketIds) async {
    final result = await _client.rpc('bulk_refund_rs_tickets', params: {
      'p_ticket_ids': ticketIds,
    });
    return (result as num?)?.toInt() ?? 0;
  }

  Future<RsProduct> adminAdjustStock(String productId, int delta) =>
      RayonSportsAdminRepository(this).adminAdjustStock(productId, delta);

  Future<FanMembership> renewMembership(String userId, DateTime newExpiry) =>
      RayonSportsAdminRepository(this).renewMembership(userId, newExpiry);

  Future<void> deleteInitiative(String initiativeId) =>
      RayonSportsAdminRepository(this).deleteInitiative(initiativeId);
}

List<RsJsonMap> _asListOfMaps(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((row) => row.map((key, val) => MapEntry('$key', val)))
        .toList(growable: false);
  }
  return const <Map<String, Object?>>[];
}

RsJsonMap _asMap(Object? value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry('$key', val));
  }
  return const <String, Object?>{};
}
