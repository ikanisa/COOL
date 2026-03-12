import 'dart:async';

import '../../features/auth/providers/auth_provider.dart';
import 'crashlytics_service.dart';
import 'engagement_tracker.dart';
import 'momo_service.dart';
import 'performance_service.dart';
import 'app_session_coordinator.dart';
import 'deep_link_coordinator.dart';
import 'trip_sync_coordinator.dart';

class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    required Future<void> Function() refreshFeatureFlags,
    required AuthState Function() readAuthState,
    required EngagementTracker engagementTracker,
    required CrashlyticsService crashlytics,
    required PerformanceService performance,
    required AppSessionCoordinator sessionCoordinator,
    required DeepLinkCoordinator deepLinkCoordinator,
    required TripSyncCoordinator tripSyncCoordinator,
  }) : _refreshFeatureFlags = refreshFeatureFlags,
       _readAuthState = readAuthState,
       _engagementTracker = engagementTracker,
       _crashlytics = crashlytics,
       _performance = performance,
       _sessionCoordinator = sessionCoordinator,
       _deepLinkCoordinator = deepLinkCoordinator,
       _tripSyncCoordinator = tripSyncCoordinator;

  final Future<void> Function() _refreshFeatureFlags;
  final AuthState Function() _readAuthState;
  final EngagementTracker _engagementTracker;
  final CrashlyticsService _crashlytics;
  final PerformanceService _performance;
  final AppSessionCoordinator _sessionCoordinator;
  final DeepLinkCoordinator _deepLinkCoordinator;
  final TripSyncCoordinator _tripSyncCoordinator;

  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    await _refreshFeatureFlags();
    await _engagementTracker.initialize();
    await _crashlytics.initialize();
    await _performance.initialize();

    MomoService.instance.setObservabilityServices(
      crashlytics: _crashlytics,
      performance: _performance,
    );

    await _engagementTracker.trackAppOpened();
    await _sessionCoordinator.bootstrap(_readAuthState());

    _tripSyncCoordinator.start();
    await _deepLinkCoordinator.start();
  }

  Future<void> handleAuthStateChanged(
    AuthState? previous,
    AuthState next,
  ) async {
    await _sessionCoordinator.handleAuthStateChanged(previous, next);
  }

  void handleAppResumed() {
    _tripSyncCoordinator.onAppResumed();
  }

  void dispose() {
    _deepLinkCoordinator.dispose();
    _tripSyncCoordinator.dispose();
    _started = false;
  }
}
