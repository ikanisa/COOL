import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_market.dart';
import '../config/country_catalog.dart';
import '../repositories/supported_countries_repository.dart';

final supportedCountriesRepositoryProvider =
    Provider<SupportedCountriesRepository>((ref) {
      return SupportedCountriesRepository();
    });

/// Rwanda-only — always returns `[AppMarket.country]`.
final supportedCountriesProvider = Provider<List<CoolCountry>>((ref) {
  return <CoolCountry>[AppMarket.country];
});
