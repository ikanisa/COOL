import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rs_models.dart';
import '../rayon_payment.dart';
import '../rs_membership_package.dart';
import '../../../partners/providers/rayon_sports_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RS Admin Providers — wraps admin CRUD methods from RayonSportsRepository
// ═══════════════════════════════════════════════════════════════════════════

/// All matches (including off-sale) for admin listing.
final rsAdminMatchesProvider = FutureProvider.autoDispose<List<RsMatch>>((
  ref,
) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  return repo.adminGetAllMatches();
});

/// All products (including inactive) for admin listing.
final rsAdminProductsProvider = FutureProvider.autoDispose<List<RsProduct>>((
  ref,
) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  return repo.adminGetAllProducts();
});

/// All shop orders (across all users) for admin listing.
final rsAdminOrdersProvider = FutureProvider.autoDispose<List<RsShopOrder>>((
  ref,
) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  return repo.adminGetAllOrders();
});

/// All tickets (optionally filtered by match) for admin listing.
final rsAdminTicketsProvider = FutureProvider.autoDispose
    .family<List<RsTicket>, String?>((ref, matchId) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.adminGetAllTickets(matchId: matchId);
    });

/// All memberships for admin listing.
final rsAdminMembersProvider = FutureProvider.autoDispose<List<FanMembership>>((
  ref,
) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  return repo.adminGetAllMembers();
});

/// All fan clubs for admin listing.
final rsAdminFanClubsProvider = FutureProvider.autoDispose<List<RsFanClub>>((
  ref,
) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  return repo.adminGetAllFanClubs();
});

/// All initiatives (including inactive) for admin listing.
final rsAdminInitiativesProvider =
    FutureProvider.autoDispose<List<RsInitiative>>((ref) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.adminGetAllInitiatives();
    });

/// Ticket stats for a specific match (admin).
final rsAdminMatchTicketStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, matchId) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.getMatchTicketStats(matchId);
    });

final rsAdminPaymentRoutesProvider =
    FutureProvider.autoDispose<List<PartnerPaymentRoute>>((ref) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.adminGetPaymentRoutes();
    });

final rsAdminMembershipPackagesProvider =
    FutureProvider.autoDispose<List<RsMembershipPackage>>((ref) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.adminGetMembershipPackages();
    });

/// Contributors for a specific initiative (admin).
final rsAdminInitiativeContributorsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, initiativeId) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.getRecentContributors(initiativeId, 50);
    });

/// Recent contributions for a specific initiative (admin).
final rsAdminInitiativeContributionsProvider = FutureProvider.autoDispose
    .family<List<RsInitiativeContribution>, String>((ref, initiativeId) async {
      final repo = ref.watch(rayonSportsRepositoryProvider);
      return repo.getRecentContributionActivity(initiativeId, 20);
    });

/// Fan engagement analytics summary.
final rsAdminFanAnalyticsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  return repo.fetchRsFanAnalytics();
});

/// Notification history.
final rsAdminNotificationsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, matchId) async {
  final repo = ref.watch(rayonSportsRepositoryProvider);
  return repo.fetchRsNotifications(matchId: matchId);
});
