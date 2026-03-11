import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/partner.dart';
import '../repositories/partner_repository.dart';

/// Singleton repository instance.
final partnerRepositoryProvider = Provider<PartnerRepository>((ref) {
  return PartnerRepository();
});

/// All active partners for a given country code.
///
/// Pass the user's country (e.g. `'RW'`) as the family parameter.
/// Pass `null` to fetch all countries.
final partnersProvider =
    FutureProvider.family<List<Partner>, String?>((ref, country) async {
  final repo = ref.read(partnerRepositoryProvider);
  return repo.fetchAll(country: country);
});

/// All active football partners for a given country.
final footballPartnersProvider =
    FutureProvider.family<List<Partner>, String?>((ref, country) async {
  final all = await ref.watch(partnersProvider(country).future);
  return all
      .where((p) => p.category == PartnerCategory.football)
      .toList();
});

/// All active bank partners for a given country.
final bankPartnersProvider =
    FutureProvider.family<List<Partner>, String?>((ref, country) async {
  final all = await ref.watch(partnersProvider(country).future);
  return all
      .where((p) => p.category == PartnerCategory.bank)
      .toList();
});

/// All active organization partners for a given country.
final orgPartnersProvider =
    FutureProvider.family<List<Partner>, String?>((ref, country) async {
  final all = await ref.watch(partnersProvider(country).future);
  return all
      .where((p) => p.category == PartnerCategory.organization)
      .toList();
});

/// Lookup a single partner by slug.
final partnerBySlugProvider =
    FutureProvider.family<Partner?, String>((ref, slug) async {
  final repo = ref.read(partnerRepositoryProvider);
  return repo.fetchBySlug(slug);
});
