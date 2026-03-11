import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../models/engagement_feature_flags.dart';
import 'firebase_bootstrap_service.dart';

class FeatureFlagsService {
  FeatureFlagsService({required FirebaseBootstrapService bootstrapService})
    : _bootstrapService = bootstrapService;

  final FirebaseBootstrapService _bootstrapService;

  EngagementFeatureFlags _current = EngagementFeatureFlags.defaults();

  EngagementFeatureFlags get current => _current;

  Future<EngagementFeatureFlags> initialize() async {
    final isAvailable = await _bootstrapService.initialize();
    if (!isAvailable) {
      return _current;
    }

    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setDefaults(_current.toRemoteConfigDefaults());
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 4),
        ),
      );
      await remoteConfig.fetchAndActivate();

      _current = EngagementFeatureFlags.fromValues(<String, Object?>{
        'engagement_enabled': remoteConfig.getBool('engagement_enabled'),
        'engagement_share_tracking_enabled': remoteConfig.getBool(
          'engagement_share_tracking_enabled',
        ),
        'engagement_group_captain_enabled': remoteConfig.getBool(
          'engagement_group_captain_enabled',
        ),
        'engagement_rayon_chapter_enabled': remoteConfig.getBool(
          'engagement_rayon_chapter_enabled',
        ),
      });
    } catch (_) {
      _current = EngagementFeatureFlags.defaults();
    }

    return _current;
  }
}
