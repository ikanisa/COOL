import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../repositories/admin_content_repository.dart';
import '../repositories/admin_momo_ops_repository.dart';
import '../repositories/admin_repository.dart';
import '../repositories/admin_users_repository.dart';

// ── Core admin repository (users, countries, dashboard, analytics) ──────

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(client: ref.read(supabaseClientProvider));
});

// ── Content management repository (partners, services, routes, etc.) ────

final adminContentRepositoryProvider = Provider<AdminContentRepository>((ref) {
  return AdminContentRepository(client: ref.read(supabaseClientProvider));
});

// ── User management repository (users, edits, mock cleanup) ────────────

final adminUsersRepositoryProvider = Provider<AdminUsersRepository>((ref) {
  return AdminUsersRepository(client: ref.read(supabaseClientProvider));
});

// ── MoMo operations repository (SMS ops, sender inventory, review) ──────

final adminMomoOpsRepositoryProvider = Provider<AdminMomoOpsRepository>((ref) {
  return AdminMomoOpsRepository(client: ref.read(supabaseClientProvider));
});

// ── Data providers ──────────────────────────────────────────────────────

final adminUsersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminUsersRepositoryProvider).fetchUsers();
});

final adminPartnersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminContentRepositoryProvider).fetchPartners();
});

final adminPartnerServicesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((
      ref,
      partnerId,
    ) async {
      return ref
          .read(adminContentRepositoryProvider)
          .fetchPartnerServices(partnerId: partnerId);
    });

final adminPartnerPaymentRoutesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref
          .read(adminContentRepositoryProvider)
          .fetchPartnerPaymentRoutes();
    });

final adminQuickActionsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminContentRepositoryProvider).fetchQuickActions();
});

final adminVehicleTypesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminContentRepositoryProvider).fetchVehicleTypes();
});

final adminAppConfigProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminContentRepositoryProvider).fetchAppConfig();
});

final adminOperationalReleaseDashboardProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref
          .read(adminRepositoryProvider)
          .fetchOperationalReleaseDashboard();
    });

final adminOperationalTriageIssuesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref.read(adminRepositoryProvider).fetchOperationalTriageIssues();
    });

final adminMomoSmsOperationalSummaryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref
          .read(adminMomoOpsRepositoryProvider)
          .fetchMomoSmsOperationalSummary();
    });

final adminMomoSmsSenderInventoryProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref
          .read(adminMomoOpsRepositoryProvider)
          .fetchMomoSmsSenderInventory();
    });

final adminMomoSmsManualReviewQueueProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref
          .read(adminMomoOpsRepositoryProvider)
          .fetchMomoSmsManualReviewQueue();
    });

final adminRecentOperationalHealthEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref
          .read(adminMomoOpsRepositoryProvider)
          .fetchRecentOperationalHealthEvents();
    });

final platformAnalyticsProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  return ref.read(adminRepositoryProvider).fetchPlatformAnalytics();
});

final adminAuditLogProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((
      ref,
      actionFilter,
    ) async {
      return ref
          .read(adminRepositoryProvider)
          .fetchAuditLog(action: actionFilter);
    });
