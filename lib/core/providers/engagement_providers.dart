import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crashlytics_service.dart';
import '../services/engagement_tracker.dart';
import '../services/fcm_service.dart';
import '../services/feature_flags_service.dart';
import '../services/firebase_bootstrap_service.dart';
import '../services/performance_service.dart';

final firebaseBootstrapServiceProvider = Provider<FirebaseBootstrapService>((
  ref,
) {
  return FirebaseBootstrapService();
});

final featureFlagsServiceProvider = Provider<FeatureFlagsService>((ref) {
  return FeatureFlagsService(
    bootstrapService: ref.read(firebaseBootstrapServiceProvider),
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
  final service = FcmService();
  ref.onDispose(service.dispose);
  return service;
});

final performanceServiceProvider = Provider<PerformanceService>((ref) {
  return PerformanceService();
});
