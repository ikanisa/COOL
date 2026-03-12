import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/mobility/services/trip_sync_service.dart';
import '../router/app_router.dart';
import '../services/app_lifecycle_coordinator.dart';
import '../services/app_session_coordinator.dart';
import '../services/deep_link_coordinator.dart';
import '../services/trip_sync_coordinator.dart';
import 'engagement_providers.dart';
import 'notification_settings_provider.dart';
import 'referral_providers.dart';

final tripSyncCoordinatorProvider = Provider<TripSyncCoordinator>((ref) {
  final coordinator = TripSyncCoordinator(
    readAuthState: () => ref.read(authProvider),
    tripSyncService: ref.read(tripSyncServiceProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final appSessionCoordinatorProvider = Provider<AppSessionCoordinator>((ref) {
  return AppSessionCoordinator(
    notificationSettings: ref.read(notificationSettingsProvider.notifier),
    engagementTracker: ref.read(engagementTrackerProvider),
    crashlytics: ref.read(crashlyticsServiceProvider),
    referralRepository: ref.read(referralRepositoryProvider),
    readReferralAttribution: () => ref.read(activeReferralAttributionProvider),
    markReferralOpened: (inviteId) {
      ref.read(activeReferralAttributionProvider.notifier).markOpened(inviteId);
    },
    tripSyncCoordinator: ref.read(tripSyncCoordinatorProvider),
  );
});

final deepLinkCoordinatorProvider = Provider<DeepLinkCoordinator>((ref) {
  final coordinator = DeepLinkCoordinator(
    readRouter: () => ref.read(appRouterProvider),
    captureReferralAttribution: (uri, {required route}) {
      ref
          .read(activeReferralAttributionProvider.notifier)
          .captureUri(uri, route: route);
    },
    markReferralInviteOpenedIfNeeded: () {
      return ref
          .read(appSessionCoordinatorProvider)
          .markReferralInviteOpenedIfNeeded();
    },
    trackDeepLinkOpened: (uri, route) {
      return ref
          .read(engagementTrackerProvider)
          .trackDeepLinkOpened(uri: uri, route: route);
    },
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final appLifecycleCoordinatorProvider = Provider<AppLifecycleCoordinator>((
  ref,
) {
  final coordinator = AppLifecycleCoordinator(
    refreshFeatureFlags: () async {
      await ref.read(featureFlagsStateProvider.notifier).refresh();
    },
    readAuthState: () => ref.read(authProvider),
    engagementTracker: ref.read(engagementTrackerProvider),
    crashlytics: ref.read(crashlyticsServiceProvider),
    performance: ref.read(performanceServiceProvider),
    sessionCoordinator: ref.read(appSessionCoordinatorProvider),
    deepLinkCoordinator: ref.read(deepLinkCoordinatorProvider),
    tripSyncCoordinator: ref.read(tripSyncCoordinatorProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final appLifecycleBindingProvider = Provider<void>((ref) {
  final coordinator = ref.read(appLifecycleCoordinatorProvider);
  final observer = _AppLifecycleObserver(coordinator);

  WidgetsBinding.instance.addObserver(observer);
  Future<void>.microtask(coordinator.start);
  ref.listen<AuthState>(authProvider, (previous, next) {
    unawaited(coordinator.handleAuthStateChanged(previous, next));
  });

  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
  });
});

class _AppLifecycleObserver with WidgetsBindingObserver {
  _AppLifecycleObserver(this._coordinator);

  final AppLifecycleCoordinator _coordinator;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _coordinator.handleAppResumed();
    }
  }
}
