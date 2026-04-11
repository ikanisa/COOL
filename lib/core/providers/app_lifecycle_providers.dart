import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/momo/providers/momo_service_provider.dart';
import '../../features/momo/providers/momo_sms_rationale_provider.dart';
import '../../features/momo/services/momo_sms_autoread_service.dart';
import '../providers/supported_countries_provider.dart';
import '../router/app_router.dart';
import '../services/app_lifecycle_coordinator.dart';
import '../services/app_session_coordinator.dart';
import '../services/app_update_service.dart';
import '../services/deep_link_coordinator.dart';
import 'app_access_provider.dart';
import 'engagement_providers.dart';
import 'notification_settings_provider.dart';
import 'supabase_client_provider.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService(ref.read(engagementTrackerProvider));
});

final momoSmsAutoreadServiceProvider = Provider<MomoSmsAutoreadService>((ref) {
  final service = MomoSmsAutoreadService(
    client: ref.read(supabaseClientProvider),
    appAccessService: ref.read(appAccessServiceProvider),
    crashlytics: ref.read(crashlyticsServiceProvider),
    consentCallback: () =>
        ref.read(momoSmsRationaleProvider).requestRationale(),
  );
  ref.onDispose(service.dispose);
  return service;
});

final appSessionCoordinatorProvider = Provider<AppSessionCoordinator>((ref) {
  return AppSessionCoordinator(
    notificationSettings: ref.read(notificationSettingsProvider.notifier),
    engagementTracker: ref.read(engagementTrackerProvider),
    crashlytics: ref.read(crashlyticsServiceProvider),
    appAccessService: ref.read(appAccessServiceProvider),
    momoSmsAutoreadService: ref.read(momoSmsAutoreadServiceProvider),
  );
});

final deepLinkCoordinatorProvider = Provider<DeepLinkCoordinator>((ref) {
  final coordinator = DeepLinkCoordinator(
    readRouter: () => ref.read(appRouterProvider),
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
    refreshSupportedCountries: () async {
      await ref.read(fetchSupportedCountriesProvider.future);
    },
    readAuthState: () => ref.read(authProvider),
    engagementTracker: ref.read(engagementTrackerProvider),
    crashlytics: ref.read(crashlyticsServiceProvider),
    performance: ref.read(performanceServiceProvider),
    sessionCoordinator: ref.read(appSessionCoordinatorProvider),
    deepLinkCoordinator: ref.read(deepLinkCoordinatorProvider),
    momoSmsAutoreadService: ref.read(momoSmsAutoreadServiceProvider),
    momoService: ref.read(momoServiceProvider),
    appUpdateService: ref.read(appUpdateServiceProvider),
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
