import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../models/partner.dart';
import '../repositories/partner_repository.dart';

/// Singleton repository instance.
final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  return PartnerRepository(client: ref.read(supabaseClientProvider));
});

/// All active partners for the fixed Rwanda market.
final partnersProvider = FutureProvider<List<Partner>>((ref) async {
  final repo = ref.read(partnerRepositoryProvider);
  return repo.fetchAll();
});

final currentCountryPartnersProvider = partnersProvider;

/// All active football partners for the fixed Rwanda market.
final footballPartnersProvider = FutureProvider<List<Partner>>((ref) async {
  final all = await ref.watch(partnersProvider.future);
  return all.where((p) => p.category == PartnerCategory.football).toList();
});

final currentCountryFootballPartnersProvider = footballPartnersProvider;

/// All active bank partners for the fixed Rwanda market.
final bankPartnersProvider = FutureProvider<List<Partner>>((ref) async {
  final all = await ref.watch(partnersProvider.future);
  return all.where((p) => p.category == PartnerCategory.bank).toList();
});

final currentCountryBankPartnersProvider = bankPartnersProvider;

/// True when the current market has at least one active bank partner.
/// Drives visibility of all group-savings-related UI surfaces.
final hasActiveBankPartnerProvider = Provider<bool>((ref) {
  return ref
      .watch(bankPartnersProvider)
      .maybeWhen(data: (list) => list.isNotEmpty, orElse: () => false);
});

/// All active organization partners for the fixed Rwanda market.
final orgPartnersProvider = FutureProvider<List<Partner>>((ref) async {
  final all = await ref.watch(partnersProvider.future);
  return all.where((p) => p.category == PartnerCategory.organization).toList();
});

final currentCountryOrgPartnersProvider = orgPartnersProvider;

/// Lookup a single partner by slug.
final partnerBySlugProvider = FutureProvider.family<Partner?, String>((
  ref,
  slug,
) async {
  final repo = ref.read(partnerRepositoryProvider);
  return repo.fetchBySlug(slug);
});

final partnerByIdProvider = FutureProvider.family<Partner?, String>((
  ref,
  id,
) async {
  final repo = ref.read(partnerRepositoryProvider);
  return repo.fetchById(id);
});
