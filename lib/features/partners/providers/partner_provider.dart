import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/partner.dart';
import '../repositories/partner_repository.dart';

/// Singleton repository instance.
final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  return PartnerRepository(client: ref.read(supabaseClientProvider));
});

/// All active partners for a given country code.
///
/// Pass the user's country (e.g. `'RW'`) as the family parameter.
/// Pass `null` to fetch all countries.
final partnersProvider = FutureProvider.family<List<Partner>, String?>((
  ref,
  country,
) async {
  final repo = ref.read(partnerRepositoryProvider);
  return repo.fetchAll(country: country);
});

final currentCountryPartnersProvider = FutureProvider<List<Partner>>((
  ref,
) async {
  final country = ref.watch(currentUserCountryCodeProvider);
  return ref.watch(partnersProvider(country).future);
});

/// All active football partners for a given country.
final footballPartnersProvider = FutureProvider.family<List<Partner>, String?>((
  ref,
  country,
) async {
  final all = await ref.watch(partnersProvider(country).future);
  return all.where((p) => p.category == PartnerCategory.football).toList();
});

final currentCountryFootballPartnersProvider = FutureProvider<List<Partner>>((
  ref,
) async {
  final country = ref.watch(currentUserCountryCodeProvider);
  return ref.watch(footballPartnersProvider(country).future);
});

/// All active bank partners for a given country.
final bankPartnersProvider = FutureProvider.family<List<Partner>, String?>((
  ref,
  country,
) async {
  final all = await ref.watch(partnersProvider(country).future);
  return all.where((p) => p.category == PartnerCategory.bank).toList();
});

final currentCountryBankPartnersProvider = FutureProvider<List<Partner>>((
  ref,
) async {
  final country = ref.watch(currentUserCountryCodeProvider);
  return ref.watch(bankPartnersProvider(country).future);
});

/// All active organization partners for a given country.
final orgPartnersProvider = FutureProvider.family<List<Partner>, String?>((
  ref,
  country,
) async {
  final all = await ref.watch(partnersProvider(country).future);
  return all.where((p) => p.category == PartnerCategory.organization).toList();
});

final currentCountryOrgPartnersProvider = FutureProvider<List<Partner>>((
  ref,
) async {
  final country = ref.watch(currentUserCountryCodeProvider);
  return ref.watch(orgPartnersProvider(country).future);
});

/// Lookup a single partner by slug.
final partnerBySlugProvider = FutureProvider.family<Partner?, String>((
  ref,
  slug,
) async {
  final repo = ref.read(partnerRepositoryProvider);
  final country = ref.watch(currentUserCountryCodeProvider);
  return repo.fetchBySlug(slug, country: country);
});
