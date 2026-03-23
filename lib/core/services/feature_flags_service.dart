import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../models/engagement_feature_flags.dart';
import 'firebase_bootstrap_service.dart';

class FeatureFlagsService {
  FeatureFlagsService({
    required FirebaseBootstrapService bootstrapService,
    Future<Map<String, Object?>> Function(EngagementFeatureFlags defaults)?
    loadRemoteConfigValues,
    Future<Map<String, Object?>> Function(Set<String> knownKeys)?
    loadAppConfigOverrides,
  }) : _bootstrapService = bootstrapService,
       _loadRemoteConfigValues = loadRemoteConfigValues,
       _loadAppConfigOverrides = loadAppConfigOverrides;

  final FirebaseBootstrapService _bootstrapService;
  final Future<Map<String, Object?>> Function(EngagementFeatureFlags defaults)?
  _loadRemoteConfigValues;
  final Future<Map<String, Object?>> Function(Set<String> knownKeys)?
  _loadAppConfigOverrides;

  EngagementFeatureFlags _current = EngagementFeatureFlags.defaults();

  EngagementFeatureFlags get current => _current;

  Future<EngagementFeatureFlags> initialize() async {
    final defaults = EngagementFeatureFlags.defaults();
    final resolvedValues = Map<String, Object?>.from(
      defaults.toRemoteConfigDefaults(),
    );

    final isAvailable = await _bootstrapService.initialize();
    if (isAvailable) {
      try {
        resolvedValues.addAll(
          await (_loadRemoteConfigValues?.call(defaults) ??
              _readRemoteConfigValues(defaults)),
        );
      } catch (_) {
        resolvedValues
          ..clear()
          ..addAll(defaults.toRemoteConfigDefaults());
      }
    }

    try {
      final overrides =
          await (_loadAppConfigOverrides?.call(
                defaults.toRemoteConfigDefaults().keys.toSet(),
              ) ??
              Future<Map<String, Object?>>.value(const <String, Object?>{}));
      resolvedValues.addAll(
        Map<String, Object?>.fromEntries(
          overrides.entries.where(
            (entry) => defaults.toRemoteConfigDefaults().containsKey(entry.key),
          ),
        ),
      );
    } catch (_) {
      // App-config overrides are best-effort and should never prevent startup.
    }

    _current = EngagementFeatureFlags.fromValues(resolvedValues);
    return _current;
  }

  Future<Map<String, Object?>> _readRemoteConfigValues(
    EngagementFeatureFlags defaults,
  ) async {
    final remoteConfig = FirebaseRemoteConfig.instance;
    await remoteConfig.setDefaults(defaults.toRemoteConfigDefaults());
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 4),
      ),
    );
    await remoteConfig.fetchAndActivate();

    return <String, Object?>{
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
      'feature_biopay_enabled': remoteConfig.getBool('feature_biopay_enabled'),
      'kill_momo_payments': remoteConfig.getBool('kill_momo_payments'),
      'kill_credit_features': remoteConfig.getBool('kill_credit_features'),
      'kill_ticket_purchase': remoteConfig.getBool('kill_ticket_purchase'),
      'kill_mobility': remoteConfig.getBool('kill_mobility'),
      'feature_momo_stage': remoteConfig.getString('feature_momo_stage'),
      'feature_momo_admin_only': remoteConfig.getBool(
        'feature_momo_admin_only',
      ),
      'feature_credit_stage': remoteConfig.getString('feature_credit_stage'),
      'feature_credit_admin_only': remoteConfig.getBool(
        'feature_credit_admin_only',
      ),
      'feature_ticket_purchase_stage': remoteConfig.getString(
        'feature_ticket_purchase_stage',
      ),
      'feature_ticket_purchase_admin_only': remoteConfig.getBool(
        'feature_ticket_purchase_admin_only',
      ),
      'feature_mobility_stage': remoteConfig.getString(
        'feature_mobility_stage',
      ),
      'feature_mobility_admin_only': remoteConfig.getBool(
        'feature_mobility_admin_only',
      ),
    };
  }
}
