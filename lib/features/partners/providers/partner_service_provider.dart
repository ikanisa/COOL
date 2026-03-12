import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/partner_service.dart';
import '../repositories/partner_service_repository.dart';

/// Provides a singleton [PartnerServiceRepository].
final partnerServiceRepositoryProvider = Provider<PartnerServiceRepository>(
  (ref) => PartnerServiceRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches all services for a given partner ID and optional country.
final partnerServicesProvider =
    FutureProvider.family<
      List<PartnerService>,
      ({String partnerId, String? country})
    >((ref, params) {
      final repo = ref.read(partnerServiceRepositoryProvider);
      return repo.fetchByPartnerId(params.partnerId, country: params.country);
    });

final currentCountryPartnerServicesProvider =
    FutureProvider.family<List<PartnerService>, String>((ref, partnerId) {
      final country = ref.watch(currentUserCountryCodeProvider);
      return ref.watch(
        partnerServicesProvider((
          partnerId: partnerId,
          country: country,
        )).future,
      );
    });

/// Fetches services by category for a given partner and optional country.
final partnerServicesByCategoryProvider =
    FutureProvider.family<
      List<PartnerService>,
      ({String partnerId, String category, String? country})
    >((ref, params) {
      final repo = ref.read(partnerServiceRepositoryProvider);
      return repo.fetchByCategory(
        params.partnerId,
        params.category,
        country: params.country,
      );
    });

final currentCountryPartnerServicesByCategoryProvider =
    FutureProvider.family<
      List<PartnerService>,
      ({String partnerId, String category})
    >((ref, params) {
      final country = ref.watch(currentUserCountryCodeProvider);
      return ref.watch(
        partnerServicesByCategoryProvider((
          partnerId: params.partnerId,
          category: params.category,
          country: country,
        )).future,
      );
    });
