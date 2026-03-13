import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/supabase_client_provider.dart';
import 'app_config_repository.dart';

/// Provides a singleton [AppConfigRepository].
final appConfigRepositoryProvider = Provider<AppConfigRepository>(
  (ref) => AppConfigRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches a single config value by key.
final appConfigProvider = FutureProvider.family<String?, String>((ref, key) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getValue(key);
});

final currentCountryAppConfigValueProvider = appConfigProvider;

/// Fetches all config values for the fixed Rwanda app shell.
final allAppConfigProvider = FutureProvider<Map<String, String>>((ref) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getAll();
});

final currentCountryAllAppConfigProvider = allAppConfigProvider;

/// Returns supported languages (English-only, no Supabase fetch).
final supportedLanguagesProvider = Provider<List<Map<String, String>>>((ref) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getSupportedLanguages();
});

/// Fetches the support WhatsApp number from app config.
final supportWhatsAppProvider = FutureProvider<String>((ref) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getSupportWhatsApp();
});

final currentCountrySupportWhatsAppProvider = supportWhatsAppProvider;

final mobilitySubscriptionMomoCodeProvider = FutureProvider<String?>((ref) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getMobilitySubscriptionMomoCode();
});

final currentCountryMobilitySubscriptionMomoCodeProvider =
    mobilitySubscriptionMomoCodeProvider;

/// Fetches credit grade thresholds from app config.
final creditGradesProvider =
    FutureProvider<({int excellent, int good, int building})>((ref) {
      final repo = ref.read(appConfigRepositoryProvider);
      return repo.getCreditGrades();
    });

/// Returns default map center (Kigali, hardcoded).
final defaultMapCenterProvider = Provider<({double lat, double lng})>((ref) {
  final repo = ref.read(appConfigRepositoryProvider);
  return repo.getDefaultMapCenter();
});
