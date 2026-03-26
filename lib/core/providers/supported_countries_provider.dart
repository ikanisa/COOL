import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/country_catalog.dart';
import '../repositories/supported_countries_repository.dart';

/// Provider for the [SupportedCountriesRepository].
final supportedCountriesRepositoryProvider =
    Provider<SupportedCountriesRepository>((ref) {
      return SupportedCountriesRepository();
    });

/// Synchronous list of supported countries for the current market.
/// Defaults to hardcoded fallback if dynamic fetch has not occurred yet.
final supportedCountriesProvider = Provider<List<CoolCountry>>((ref) {
  final repository = ref.watch(supportedCountriesRepositoryProvider);
  return repository.getSupportedCountries();
});

/// Async provider for fetching supported countries from Supabase.
/// Should be awaited during app initialization to populate the cache.
final fetchSupportedCountriesProvider = FutureProvider<List<CoolCountry>>((
  ref,
) async {
  final repository = ref.read(supportedCountriesRepositoryProvider);
  return repository.fetchSupportedCountries();
});
