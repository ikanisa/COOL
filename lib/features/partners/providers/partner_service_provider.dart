import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../models/partner_service.dart';
import '../repositories/partner_service_repository.dart';

/// Provides a singleton [PartnerServiceRepository].
final partnerServiceRepositoryProvider = Provider<PartnerServiceRepository>(
  (ref) => PartnerServiceRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches all services for a given partner ID.
final partnerServicesProvider =
    FutureProvider.family<List<PartnerService>, String>((ref, partnerId) {
      final repo = ref.read(partnerServiceRepositoryProvider);
      return repo.fetchByPartnerId(partnerId);
    });

final currentCountryPartnerServicesProvider = partnerServicesProvider;

/// Fetches services by category for a given partner.
final partnerServicesByCategoryProvider =
    FutureProvider.family<
      List<PartnerService>,
      ({String partnerId, String category})
    >((ref, params) {
      final repo = ref.read(partnerServiceRepositoryProvider);
      return repo.fetchByCategory(params.partnerId, params.category);
    });

final currentCountryPartnerServicesByCategoryProvider =
    partnerServicesByCategoryProvider;
