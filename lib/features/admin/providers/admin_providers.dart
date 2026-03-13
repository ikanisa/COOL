import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../repositories/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(client: ref.read(supabaseClientProvider));
});

final adminUsersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminRepositoryProvider).fetchUsers();
});

final adminPartnersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminRepositoryProvider).fetchPartners();
});

final adminPartnerServicesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String?>((
      ref,
      partnerId,
    ) async {
      return ref
          .read(adminRepositoryProvider)
          .fetchPartnerServices(partnerId: partnerId);
    });

final adminPartnerPaymentRoutesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref.read(adminRepositoryProvider).fetchPartnerPaymentRoutes();
    });

final adminQuickActionsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminRepositoryProvider).fetchQuickActions();
});

final adminVehicleTypesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminRepositoryProvider).fetchVehicleTypes();
});

final adminCountriesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminRepositoryProvider).fetchCountries();
});

final adminMomoValidationIssuesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref.read(adminRepositoryProvider).fetchMomoValidationIssues();
    });

final adminAppConfigProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(adminRepositoryProvider).fetchAppConfig();
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

final adminRecentOperationalHealthEventsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      return ref
          .read(adminRepositoryProvider)
          .fetchRecentOperationalHealthEvents();
    });
