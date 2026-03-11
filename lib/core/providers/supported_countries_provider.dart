import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/country_catalog.dart';
import '../repositories/supported_countries_repository.dart';

final supportedCountriesRepositoryProvider =
    Provider<SupportedCountriesRepository>((ref) {
      return SupportedCountriesRepository();
    });

final supportedCountriesProvider = FutureProvider<List<CoolCountry>>((ref) {
  final repository = ref.watch(supportedCountriesRepositoryProvider);
  return repository.getSupportedCountries();
});
