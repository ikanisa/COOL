import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config_repository.dart';
import '../models/engagement_feature_flags.dart';
import '../providers/supabase_client_provider.dart';
import '../services/app_update_service.dart';
import '../services/crashlytics_service.dart';
import '../services/engagement_tracker.dart';
import 'hive_providers.dart';
import '../services/fcm_service.dart';
import '../services/feature_flags_service.dart';
import '../services/firebase_bootstrap_service.dart';
import '../services/performance_service.dart';
import '../services/screen_security_service.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService(ref.read(engagementTrackerProvider));
});

final firebaseBootstrapServiceProvider = Provider<FirebaseBootstrapService>((
  ref,
) {
  return FirebaseBootstrapService();
});

final featureFlagsServiceProvider = Provider<FeatureFlagsService>((ref) {
  return FeatureFlagsService(
    bootstrapService: ref.read(firebaseBootstrapServiceProvider),
    loadAppConfigOverrides: (knownKeys) async {
      final repo = AppConfigRepository(
        client: ref.read(supabaseClientProvider),
      );
      final values = await repo.getAll();
      return Map<String, Object?>.fromEntries(
        values.entries.where((entry) => knownKeys.contains(entry.key)),
      );
    },
  );
});

final featureFlagsStateProvider =
    StateNotifierProvider<FeatureFlagsNotifier, EngagementFeatureFlags>((ref) {
      return FeatureFlagsNotifier(
        service: ref.read(featureFlagsServiceProvider),
      );
    });

final engagementTrackerProvider = Provider<EngagementTracker>((ref) {
  return EngagementTracker(
    bootstrapService: ref.read(firebaseBootstrapServiceProvider),
    featureFlagsService: ref.read(featureFlagsServiceProvider),
  );
});

final crashlyticsServiceProvider = Provider<CrashlyticsService>((ref) {
  return CrashlyticsService();
});

final fcmServiceProvider = Provider<FcmService>((ref) {
  final client = ref.read(supabaseClientProvider);
  final service = FcmService(
    preferenceStore: HiveFcmPreferenceStore(
      openBox: ref.read(hiveOpenBoxProvider),
    ),
    topicPreferenceStore: HiveFcmTopicPreferenceStore(
      openBox: ref.read(hiveOpenBoxProvider),
    ),
    tokenRepository: SupabaseFcmTokenRepository(clientFactory: () => client),
  );
  ref.onDispose(service.dispose);
  return service;
});

final performanceServiceProvider = Provider<PerformanceService>((ref) {
  return PerformanceService();
});

final screenSecurityServiceProvider = Provider<ScreenSecurityService>((ref) {
  return ScreenSecurityService();
});

class FeatureFlagsNotifier extends StateNotifier<EngagementFeatureFlags> {
  FeatureFlagsNotifier({required FeatureFlagsService service})
    : _service = service,
      super(service.current);

  final FeatureFlagsService _service;

  Future<EngagementFeatureFlags> refresh() async {
    final next = await _service.initialize();
    state = next;
    return next;
  }
}
