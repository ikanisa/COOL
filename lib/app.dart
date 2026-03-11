import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/deep_link_config.dart';
import 'core/l10n/locale_provider.dart';
import 'core/providers/engagement_providers.dart';
import 'core/providers/notification_settings_provider.dart';
import 'core/providers/referral_providers.dart';
import 'core/router/app_router.dart';
import 'core/services/momo_service.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/mobility/services/trip_sync_service.dart';

import 'l10n/app_localizations.dart';


/// Root application widget.
///
/// Sets up [MaterialApp.router] with:
/// - GoRouter navigation
/// - Dark theme via [AppTheme.dark]
/// - English + French localizations
class CoolApp extends ConsumerStatefulWidget {
  const CoolApp({super.key});

  @override
  ConsumerState<CoolApp> createState() => _CoolAppState();
}

class _CoolAppState extends ConsumerState<CoolApp> with WidgetsBindingObserver {
  late final ProviderSubscription<AuthState> _authSubscription;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _deepLinkSubscription;
  Timer? _tripSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appLinks = AppLinks();
    unawaited(_initializeEngagement());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authProvider);
      if (authState.session != null) {
        _triggerPendingTripSync('session_restore');
      }
    });

    _tripSyncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _triggerPendingTripSync('periodic_poll');
    });

    _authSubscription = ref.listenManual<AuthState>(authProvider, (
      previous,
      next,
    ) {
      final tracker = ref.read(engagementTrackerProvider);
      final crashlytics = ref.read(crashlyticsServiceProvider);
      final notifications = ref.read(notificationSettingsProvider.notifier);
      final hadSession = previous?.session != null;
      final hasSession = next.session != null;
      final previousUserId = previous?.user?.id ?? previous?.session?.user.id;

      if (previous?.user?.id != next.user?.id) {
        if (next.user != null) {
          unawaited(tracker.identifyUser(next.user!));
          unawaited(crashlytics.identifyUser(next.user!.id));
        } else if (!hasSession) {
          unawaited(tracker.clearUser());
          unawaited(crashlytics.clearUser());
        }
      }

      if (!hadSession && hasSession) {
        unawaited(_markReferralInviteOpenedIfNeeded());
        unawaited(notifications.initializeForAuthState(next));
        _triggerPendingTripSync('auth_transition');
        unawaited(
          tracker.trackSessionStarted(
            userId: next.user?.id ?? next.session!.user.id,
            isAuthenticated: true,
            isProfileComplete: next.user?.isProfileComplete ?? false,
            source: 'auth_transition',
          ),
        );
      }

      if (hadSession &&
          hasSession &&
          previous?.user?.country != next.user?.country) {
        unawaited(notifications.syncTopicsForAuthState(next));
      }

      if (hadSession && !hasSession) {
        unawaited(tracker.clearUser());
        unawaited(crashlytics.clearUser());
        if (previousUserId != null && previousUserId.isNotEmpty) {
          unawaited(notifications.clearSession(userId: previousUserId));
        }
      }
    });

    unawaited(_initializeDeepLinks());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tripSyncTimer?.cancel();
    _deepLinkSubscription?.cancel();
    _authSubscription.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerPendingTripSync('app_resumed');
    }
  }

  Future<void> _initializeDeepLinks() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      _handleDeepLink(initialUri);
    } catch (_) {
      // Ignore deep-link bootstrap failures and fall back to normal startup.
    }

    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (_) {
        // Ignore malformed links instead of interrupting the app session.
      },
    );
  }

  Future<void> _initializeEngagement() async {
    final flags = ref.read(featureFlagsServiceProvider);
    final tracker = ref.read(engagementTrackerProvider);
    final crashlytics = ref.read(crashlyticsServiceProvider);
    final performance = ref.read(performanceServiceProvider);

    await flags.initialize();
    await tracker.initialize();
    await crashlytics.initialize();
    await performance.initialize();

    // Wire Firebase observability into MoMo singleton.
    MomoService.instance.setObservabilityServices(
      crashlytics: crashlytics,
      performance: performance,
    );

    await tracker.trackAppOpened();

    final authState = ref.read(authProvider);
    if (authState.user != null) {
      await tracker.identifyUser(authState.user!);
      await crashlytics.identifyUser(authState.user!.id);
    }

    if (authState.session != null) {
      await _markReferralInviteOpenedIfNeeded();
      await _initializeFcm(authState);
      await tracker.trackSessionStarted(
        userId: authState.user?.id ?? authState.session!.user.id,
        isAuthenticated: true,
        isProfileComplete: authState.user?.isProfileComplete ?? false,
        source: 'app_launch',
      );
    }
  }

  Future<void> _initializeFcm(AuthState authState) async {
    await ref
        .read(notificationSettingsProvider.notifier)
        .initializeForAuthState(authState);
  }

  void _triggerPendingTripSync(String source) {
    final session = ref.read(authProvider).session;
    if (session == null) {
      return;
    }

    unawaited(
      ref
          .read(tripSyncServiceProvider)
          .syncPendingTrips(userId: session.user.id, source: source),
    );
  }

  void _handleDeepLink(Uri? uri) {
    if (!mounted || uri == null) {
      return;
    }

    final route = DeepLinkConfig.routeForUri(uri);
    if (route == null) {
      return;
    }

    ref
        .read(activeReferralAttributionProvider.notifier)
        .captureUri(uri, route: route);
    unawaited(_markReferralInviteOpenedIfNeeded());
    unawaited(
      ref
          .read(engagementTrackerProvider)
          .trackDeepLinkOpened(uri: uri, route: route),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final router = ref.read(appRouterProvider);
      if (router.routeInformationProvider.value.uri.toString() == route) {
        return;
      }
      router.go(route);
    });
  }

  Future<void> _markReferralInviteOpenedIfNeeded() async {
    final session = ref.read(authProvider).session;
    final attribution = ref.read(activeReferralAttributionProvider);
    if (session == null || attribution == null || attribution.openedLogged) {
      return;
    }

    try {
      await ref
          .read(referralRepositoryProvider)
          .markInviteOpened(attribution.inviteId);
      ref
          .read(activeReferralAttributionProvider.notifier)
          .markOpened(attribution.inviteId);
    } catch (_) {
      // Keep referral attribution best-effort so deep-link routing still works.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'Cool',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    );
  }
}

