import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../providers/supabase_client_provider.dart';
import 'app_config_repository.dart';

/// Provides a singleton [AppConfigRepository].
final appConfigRepositoryProvider = Provider<AppConfigRepository>(
  (ref) => AppConfigRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches a single config value by key and optional country.
final appConfigProvider =
    FutureProvider.family<String?, ({String key, String? country})>((
      ref,
      params,
    ) {
      final repo = ref.read(appConfigRepositoryProvider);
      return repo.getValue(params.key, country: params.country);
    });

final currentCountryAppConfigValueProvider =
    FutureProvider.family<String?, String>((ref, key) {
      final country = ref.watch(currentUserCountryCodeProvider);
      return ref.watch(appConfigProvider((key: key, country: country)).future);
    });

/// Fetches all config values, optionally filtered by country.
final allAppConfigProvider =
    FutureProvider.family<Map<String, String>, String?>((ref, country) {
      final repo = ref.read(appConfigRepositoryProvider);
      return repo.getAll(country: country);
    });

final currentCountryAllAppConfigProvider = FutureProvider<Map<String, String>>((
  ref,
) {
  final country = ref.watch(currentUserCountryCodeProvider);
  return ref.watch(allAppConfigProvider(country).future);
});

/// Fetches supported languages from app config.
final supportedLanguagesProvider = FutureProvider<List<Map<String, String>>>((
  ref,
) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getSupportedLanguages();
});

/// Fetches the support WhatsApp number from app config.
final supportWhatsAppProvider = FutureProvider<String>((ref) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getSupportWhatsApp();
});

final currentCountrySupportWhatsAppProvider = FutureProvider<String>((ref) {
  final repo = ref.read(appConfigRepositoryProvider);
  final country = ref.watch(currentUserCountryCodeProvider);
  return repo.getSupportWhatsApp(country: country);
});

final mobilitySubscriptionMomoCodeProvider =
    FutureProvider.family<String?, String?>((ref, country) {
      final repo = ref.read(appConfigRepositoryProvider);
      return repo.getMobilitySubscriptionMomoCode(country: country);
    });

final currentCountryMobilitySubscriptionMomoCodeProvider =
    FutureProvider<String?>((ref) {
      final country = ref.watch(currentUserCountryCodeProvider);
      return ref.watch(mobilitySubscriptionMomoCodeProvider(country).future);
    });

/// Fetches credit grade thresholds from app config.
final creditGradesProvider =
    FutureProvider<({int excellent, int good, int building})>((ref) {
      final repo = ref.read(appConfigRepositoryProvider);
      return repo.getCreditGrades();
    });

/// Fetches default map center coordinates for a given country.
final defaultMapCenterProvider =
    FutureProvider.family<({double lat, double lng})?, String?>((ref, country) {
      final repo = ref.read(appConfigRepositoryProvider);
      return repo.getDefaultMapCenter(country: country);
    });

final currentCountryDefaultMapCenterProvider =
    FutureProvider<({double lat, double lng})?>((ref) {
      final country = ref.watch(currentUserCountryCodeProvider);
      return ref.watch(defaultMapCenterProvider(country).future);
    });
