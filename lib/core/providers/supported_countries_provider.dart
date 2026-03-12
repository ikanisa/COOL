import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/country_catalog.dart';
import '../repositories/supported_countries_repository.dart';
import 'supabase_client_provider.dart';

final supportedCountriesRepositoryProvider =
    Provider<SupportedCountriesRepository>((ref) {
      return SupportedCountriesRepository(
        client: ref.read(supabaseClientProvider),
      );
    });

final supportedCountriesProvider = FutureProvider<List<CoolCountry>>((ref) {
  final repository = ref.watch(supportedCountriesRepositoryProvider);
  return repository.getSupportedCountries();
});
