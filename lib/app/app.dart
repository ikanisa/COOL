import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/collect_notification_service.dart';
import '../core/security/sms_access_channel.dart';
import '../shared/providers/collect_app_state.dart';
import '../shared/repositories/collect_repository.dart';
import '../shared/repositories/pending_shared_group_intent_store.dart';
import '../shared/widgets/collect_components.dart';
import 'env/app_env.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/collect_theme_controller.dart';

final collectIncomingAppLinksProvider = Provider<Stream<Uri>>(
  (ref) => const Stream<Uri>.empty(),
);

class CollectApp extends ConsumerWidget {
  const CollectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(collectThemeModeProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: CollectColors.transparentColor,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: CollectColors.referenceChromeBlack,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: CollectColors.transparentColor,
      ),
      child: _PendingSharedGroupIntentRecoveryHost(
        child: _NotificationIntentHost(
          child: _MomoReceiptSmsReceiverHost(
            child: _NotificationRegistrationHost(
              child: MaterialApp.router(
                title: 'Collect',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                highContrastTheme: AppTheme.highContrastLight(),
                highContrastDarkTheme: AppTheme.highContrastDark(),
                themeMode: themeMode,
                routerConfig: router,
                builder: (context, child) {
                  return _CollectConnectivityOverlay(
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs in Android builds that enable Rwanda MoMo receipt reconciliation.
/// Access remains off until an authenticated Rwanda member gives consent.
class _MomoReceiptSmsReceiverHost extends ConsumerStatefulWidget {
  const _MomoReceiptSmsReceiverHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_MomoReceiptSmsReceiverHost> createState() =>
      _MomoReceiptSmsReceiverHostState();
}

class _MomoReceiptSmsReceiverHostState
    extends ConsumerState<_MomoReceiptSmsReceiverHost>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _subscription;
  Future<int>? _syncInFlight;
  late final bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = ref.read(appEnvProvider).enableAndroidSmsAccess;
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = const SmsAccessChannel().pendingSmsEvents.listen(
      (_) => _sync(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    if (_enabled) WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _sync() {
    if (!_enabled || _syncInFlight != null) return;
    final sync = ref
        .read(collectRepositoryProvider.notifier)
        .syncPendingSmsAccess();
    _syncInFlight = sync;
    unawaited(
      sync.catchError((_) => 0).whenComplete(() {
        if (identical(_syncInFlight, sync)) _syncInFlight = null;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled) {
      ref.listen<String?>(
        collectRepositoryProvider.select((state) => state.currentProfile?.id),
        (_, current) {
          if (current != null) _sync();
        },
      );
    }
    return widget.child;
  }
}

class _NotificationIntentHost extends ConsumerStatefulWidget {
  const _NotificationIntentHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_NotificationIntentHost> createState() =>
      _NotificationIntentHostState();
}

class _NotificationIntentHostState
    extends ConsumerState<_NotificationIntentHost> {
  StreamSubscription<CollectNotificationIntent>? _subscription;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(collectNotificationServiceProvider);
    _subscription = notifications.notificationTapPayloads.listen(
      _scheduleNavigation,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _scheduleNavigation(CollectNotificationIntent intent) {
    final eventId = intent.eventId;
    if (eventId != null) {
      unawaited(_markNotificationRead(eventId));
    }
    final target = intent.deepLink;
    final router = ref.read(appRouterProvider);
    if (router.routeInformationProvider.value.uri.toString() == target) return;
    router.go(target);
  }

  Future<void> _markNotificationRead(String eventId) async {
    try {
      await ref
          .read(collectRepositoryProvider.notifier)
          .markNotificationRead(eventId);
    } catch (_) {
      // Navigation remains available if read-receipt sync is temporarily down.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PendingSharedGroupIntentRecoveryHost extends ConsumerStatefulWidget {
  const _PendingSharedGroupIntentRecoveryHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_PendingSharedGroupIntentRecoveryHost> createState() =>
      _PendingSharedGroupIntentRecoveryHostState();
}

class _PendingSharedGroupIntentRecoveryHostState
    extends ConsumerState<_PendingSharedGroupIntentRecoveryHost> {
  StreamSubscription<Uri>? _appLinkSubscription;
  var _recoveryScheduled = false;
  String? _joinInFlightSlug;
  String? _navigationTarget;

  @override
  void initState() {
    super.initState();
    _appLinkSubscription = ref
        .read(collectIncomingAppLinksProvider)
        .listen(
          (uri) => unawaited(_acceptIncomingAppLink(uri)),
          onError: (_) {
            // Platform-channel availability must not make normal app startup
            // fail. A received link still fails closed if it cannot persist.
          },
        );
    _scheduleRecovery();
  }

  @override
  void dispose() {
    unawaited(_appLinkSubscription?.cancel());
    super.dispose();
  }

  Future<void> _acceptIncomingAppLink(Uri uri) async {
    final target = collectAppLinkTargetFromUri(uri);
    if (target == null) return;
    switch (target.kind) {
      case CollectAppLinkKind.group:
        final slug = target.value!;
        try {
          await ref.read(pendingSharedGroupSlugProvider.notifier).retain(slug);
          if (!mounted) return;
          if (!ref.read(profileReadinessProvider).readyForGroupCreation) {
            _scheduleNavigation('/c/${Uri.encodeComponent(slug)}');
          } else {
            _scheduleRecovery();
          }
        } catch (_) {
          // Never navigate from a link that was not durably retained.
        }
        return;
      case CollectAppLinkKind.app:
      case CollectAppLinkKind.invite:
        _scheduleNavigation(
          ref.read(collectRepositoryProvider).currentProfile == null
              ? '/auth'
              : '/home',
        );
        return;
    }
  }

  void _scheduleRecovery() {
    if (_recoveryScheduled) return;
    _recoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoveryScheduled = false;
      unawaited(_recover());
    });
  }

  Future<void> _recover() async {
    final pendingIntent = ref.read(pendingSharedGroupSlugProvider.notifier);
    final slug = await pendingIntent.current();
    if (!mounted || slug == null) return;
    final readiness = ref.read(profileReadinessProvider);
    if (!readiness.readyForGroupCreation) return;

    final router = ref.read(appRouterProvider);
    final intentPath = '/c/${Uri.encodeComponent(slug)}';
    if (router.routeInformationProvider.value.uri.path == intentPath) return;
    if (_joinInFlightSlug == slug) return;
    _joinInFlightSlug = slug;
    try {
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .joinGroupBySlug(slug);
      final cleared = await pendingIntent.clearIfMatches(slug);
      if (!mounted || !cleared) return;
      _scheduleNavigation('/groups/${collection.id}');
    } catch (_) {
      if (!mounted) return;
      // Keep the durable intent and hand the failure to the normal link route,
      // which exposes its governed retry state.
      _scheduleNavigation(intentPath);
    } finally {
      if (_joinInFlightSlug == slug) _joinInFlightSlug = null;
    }
  }

  void _scheduleNavigation(String target) {
    final router = ref.read(appRouterProvider);
    if (router.routeInformationProvider.value.uri.path == target) return;
    if (_navigationTarget == target) return;
    _navigationTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigationTarget = null;
      final currentRouter = ref.read(appRouterProvider);
      if (currentRouter.routeInformationProvider.value.uri.path == target) {
        return;
      }
      currentRouter.go(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingSharedGroupSlugProvider, (_, _) {
      _scheduleRecovery();
    });
    ref.listen<ProfileReadiness>(profileReadinessProvider, (_, _) {
      _scheduleRecovery();
    });
    return widget.child;
  }
}

class _CollectConnectivityOverlay extends ConsumerWidget {
  const _CollectConnectivityOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityStatusProvider);
    final overlayStatus = connectivityOverlayStatus(status);
    final compactWidth = MediaQuery.sizeOf(context).width < 600;
    final topPadding = compactWidth ? 64.0 : CollectSpacing.x2;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  CollectSpacing.x4,
                  topPadding,
                  CollectSpacing.x4,
                  0,
                ),
                child: AnimatedSwitcher(
                  duration: CollectMotion.duration(
                    context,
                    CollectMotion.medium,
                  ),
                  child: CollectConnectivityBanner(
                    key: ValueKey<ConnectivityStatus>(overlayStatus),
                    status: overlayStatus,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cached-data state is already shown by [ScreenScaffold] in the normal
/// document flow. Keeping it out of the global overlay avoids covering screen
/// titles while preserving overlay alerts for degraded and offline failures.
ConnectivityStatus connectivityOverlayStatus(ConnectivityStatus status) {
  return status == ConnectivityStatus.offlineStale
      ? ConnectivityStatus.online
      : status;
}

class _NotificationRegistrationHost extends ConsumerStatefulWidget {
  const _NotificationRegistrationHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_NotificationRegistrationHost> createState() =>
      _NotificationRegistrationHostState();
}

class _NotificationRegistrationHostState
    extends ConsumerState<_NotificationRegistrationHost>
    with WidgetsBindingObserver {
  Future<void>? _syncInFlight;
  var _syncRequested = false;
  var _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncRuntime());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _syncRuntime();
    }
  }

  void _syncRuntime() {
    if (_syncInFlight != null) {
      _syncRequested = true;
      return;
    }
    _syncRequested = false;
    final sync = _syncNotificationRegistration();
    _syncInFlight = sync;
    unawaited(
      sync.whenComplete(() {
        if (identical(_syncInFlight, sync)) {
          _syncInFlight = null;
          if (_syncRequested && mounted) {
            _syncRuntime();
          }
        }
      }),
    );
  }

  Future<void> _syncNotificationRegistration() async {
    try {
      final notifications = ref.read(collectNotificationServiceProvider);
      await notifications.initialize();
      final notificationsEnabled = await notifications
          .areNotificationsEnabled();
      final permissionState = ref.read(notificationPermissionStatusProvider);
      if (notificationsEnabled) {
        ref.read(notificationPermissionStatusProvider.notifier).state =
            CollectDevicePermissionStatus.granted;
        final repository = ref.read(collectRepositoryProvider.notifier);
        unawaited(notifications.registerDevice(repository));
      } else if (permissionState == CollectDevicePermissionStatus.granted) {
        // A previously granted permission becoming disabled is a denial.
        // Preserve both the initial not-requested state and an explicit denial:
        // Android's resumed callback can race the result of the native prompt.
        ref.read(notificationPermissionStatusProvider.notifier).state =
            CollectDevicePermissionStatus.denied;
      }
    } catch (_) {
      // Device notification registration is retried on the next resume.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
