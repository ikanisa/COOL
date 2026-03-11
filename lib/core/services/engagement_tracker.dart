import 'package:firebase_analytics/firebase_analytics.dart';

import '../../features/auth/models/user_profile.dart';
import '../models/engagement_event.dart';
import 'feature_flags_service.dart';
import 'firebase_bootstrap_service.dart';

class EngagementTracker {
  EngagementTracker({
    required FirebaseBootstrapService bootstrapService,
    required FeatureFlagsService featureFlagsService,
  }) : _bootstrapService = bootstrapService,
       _featureFlagsService = featureFlagsService;

  final FirebaseBootstrapService _bootstrapService;
  final FeatureFlagsService _featureFlagsService;

  FirebaseAnalytics? _analytics;
  bool _didInitialize = false;

  Future<void> initialize() async {
    if (_didInitialize) {
      return;
    }

    _didInitialize = true;
    final isAvailable = await _bootstrapService.initialize();
    if (!isAvailable) {
      return;
    }

    try {
      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(
        _featureFlagsService.current.engagementEnabled,
      );
    } catch (_) {
      _analytics = null;
    }
  }

  Future<void> identifyUser(UserProfile user) async {
    await initialize();
    if (!_featureFlagsService.current.engagementEnabled || _analytics == null) {
      return;
    }

    await _analytics!.setUserId(id: user.id);
    await _analytics!.setUserProperty(name: 'country', value: user.country);
    await _analytics!.setUserProperty(
      name: 'language_code',
      value: user.languageCode,
    );
    await _analytics!.setUserProperty(
      name: 'momo_provider',
      value: user.momoProvider,
    );
    await _analytics!.setUserProperty(
      name: 'is_driver',
      value: user.isDriver ? 'true' : 'false',
    );
  }

  Future<void> clearUser() async {
    await initialize();
    if (_analytics == null) {
      return;
    }

    await _analytics!.setUserId();
  }

  Future<void> trackAppOpened() async {
    await track(const EngagementEvent(name: EngagementEventName.appOpened));
  }

  Future<void> trackSessionStarted({
    required String userId,
    required bool isAuthenticated,
    required bool isProfileComplete,
    required String source,
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.sessionStarted,
        parameters: <String, Object?>{
          'user_id': userId,
          'authenticated': isAuthenticated,
          'profile_complete': isProfileComplete,
          'source': source,
        },
      ),
    );
  }

  Future<void> trackDeepLinkOpened({
    required Uri uri,
    required String route,
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.deepLinkOpened,
        parameters: <String, Object?>{
          'scheme': uri.scheme,
          'host': uri.host,
          'path': uri.path,
          'route': route,
          'has_query': uri.hasQuery,
          'campaign': uri.queryParameters['campaign'],
          'referral_invite_id': uri.queryParameters['ri'],
        },
      ),
    );
  }

  Future<void> trackInviteSent({
    required String channel,
    required String inviteUrl,
    String? targetType,
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.inviteSent,
        parameters: <String, Object?>{
          'channel': channel,
          'invite_url': inviteUrl,
          'target_type': targetType,
        },
      ),
    );
  }

  Future<void> trackInviteOpened({
    required String inviteCode,
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.inviteOpened,
        parameters: <String, Object?>{
          'invite_code': inviteCode.toUpperCase(),
          'campaign': queryParameters['campaign'],
          'referral_invite_id': queryParameters['ri'],
        },
      ),
    );
  }

  Future<void> trackInviteAccepted({
    required String inviteCode,
    required String groupId,
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.inviteAccepted,
        parameters: <String, Object?>{
          'invite_code': inviteCode.toUpperCase(),
          'group_id': groupId,
          'campaign': queryParameters['campaign'],
          'referral_invite_id': queryParameters['ri'],
        },
      ),
    );
  }

  Future<void> trackShareAction({
    required String channel,
    required String targetType,
    required String targetUrl,
  }) async {
    if (!_featureFlagsService.current.shareTrackingEnabled) {
      return;
    }

    await track(
      EngagementEvent(
        name: EngagementEventName.shareAction,
        parameters: <String, Object?>{
          'channel': channel,
          'target_type': targetType,
          'target_url': targetUrl,
        },
      ),
    );
  }

  Future<void> trackTripScheduled({
    required String role,
    required String vehicleType,
    required bool recurring,
    required bool returnTrip,
    required bool storedOffline,
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.tripScheduled,
        parameters: <String, Object?>{
          'role': role,
          'veh_type': vehicleType,
          'recurring': recurring,
          'return_trip': returnTrip,
          'stored_offline': storedOffline,
        },
      ),
    );
  }

  Future<void> trackDriverWentOnline({
    required bool isOnline,
    required String vehicleType,
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.driverWentOnline,
        parameters: <String, Object?>{
          'is_online': isOnline,
          'veh_type': vehicleType,
        },
      ),
    );
  }

  Future<void> trackDiscoverTabSwitch({
    required String fromTab,
    required String toTab,
  }) async {
    await track(
      EngagementEvent(
        name: EngagementEventName.discoverTabSwitch,
        parameters: <String, Object?>{'from_tab': fromTab, 'to_tab': toTab},
      ),
    );
  }

  Future<void> track(EngagementEvent event) async {
    await initialize();
    if (!_featureFlagsService.current.engagementEnabled || _analytics == null) {
      return;
    }

    await _analytics!.logEvent(
      name: event.name.value,
      parameters: event.analyticsParameters,
    );
  }
}
