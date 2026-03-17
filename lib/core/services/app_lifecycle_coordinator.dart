import 'dart:async';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/momo/services/momo_sms_autoread_service.dart';
import 'crashlytics_service.dart';
import 'engagement_tracker.dart';
import 'momo_service.dart';
import 'performance_service.dart';
import 'app_session_coordinator.dart';
import 'app_update_service.dart';
import 'deep_link_coordinator.dart';
import 'trip_sync_coordinator.dart';

class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    required Future<void> Function() refreshFeatureFlags,
    required Future<void> Function() refreshSupportedCountries,
    required AuthState Function() readAuthState,
    required EngagementTracker engagementTracker,
    required CrashlyticsService crashlytics,
    required PerformanceService performance,
    required AppSessionCoordinator sessionCoordinator,
    required DeepLinkCoordinator deepLinkCoordinator,
    required TripSyncCoordinator tripSyncCoordinator,
    required MomoSmsAutoreadService momoSmsAutoreadService,
    required MomoService momoService,
    required AppUpdateService appUpdateService,
  }) : _refreshFeatureFlags = refreshFeatureFlags,
       _refreshSupportedCountries = refreshSupportedCountries,
       _readAuthState = readAuthState,
       _engagementTracker = engagementTracker,
       _crashlytics = crashlytics,
       _performance = performance,
       _sessionCoordinator = sessionCoordinator,
       _deepLinkCoordinator = deepLinkCoordinator,
       _tripSyncCoordinator = tripSyncCoordinator,
       _momoSmsAutoreadService = momoSmsAutoreadService,
       _momoService = momoService,
       _appUpdateService = appUpdateService;

  final Future<void> Function() _refreshFeatureFlags;
  final Future<void> Function() _refreshSupportedCountries;
  final AuthState Function() _readAuthState;
  final EngagementTracker _engagementTracker;
  final CrashlyticsService _crashlytics;
  final PerformanceService _performance;
  final AppSessionCoordinator _sessionCoordinator;
  final DeepLinkCoordinator _deepLinkCoordinator;
  final TripSyncCoordinator _tripSyncCoordinator;
  final MomoSmsAutoreadService _momoSmsAutoreadService;
  final MomoService _momoService;
  final AppUpdateService _appUpdateService;

  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    await Future.wait([_refreshFeatureFlags(), _refreshSupportedCountries()]);
    await _engagementTracker.initialize();
    await _crashlytics.initialize();
    await _performance.initialize();

    _momoService.setObservabilityServices(
      crashlytics: _crashlytics,
      performance: _performance,
    );

    await _engagementTracker.trackAppOpened();
    await _sessionCoordinator.bootstrap(_readAuthState());

    _tripSyncCoordinator.start();
    await _deepLinkCoordinator.start();

    unawaited(_appUpdateService.checkForUpdate());
  }

  Future<void> handleAuthStateChanged(
    AuthState? previous,
    AuthState next,
  ) async {
    await _sessionCoordinator.handleAuthStateChanged(previous, next);
  }

  void handleAppResumed() {
    _tripSyncCoordinator.onAppResumed();
    unawaited(_momoSmsAutoreadService.refresh());
    unawaited(_appUpdateService.checkForUpdate());
  }

  void dispose() {
    _deepLinkCoordinator.dispose();
    _tripSyncCoordinator.dispose();
    _started = false;
  }
}
