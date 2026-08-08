import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/collect_notification_service.dart';
import '../shared/providers/collect_app_state.dart';
import '../shared/repositories/collect_repository.dart';
import '../shared/repositories/pending_shared_group_intent_store.dart';
import '../shared/widgets/collect_components.dart';
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
          child: _SmsAccessSyncHost(
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
    );
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
    final slug = pendingSharedGroupSlugFromAppLink(uri);
    if (slug == null) return;
    try {
      await ref.read(pendingSharedGroupSlugProvider.notifier).retain(slug);
      if (!mounted) return;
      if (!ref.read(profileReadinessProvider).readyForGroupCreation) {
        _scheduleNavigation('/c/${Uri.encodeComponent(slug)}');
      }
    } catch (_) {
      // Never navigate from a link that was not durably retained.
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
                    key: ValueKey<ConnectivityStatus>(status),
                    status: status,
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

class _SmsAccessSyncHost extends ConsumerStatefulWidget {
  const _SmsAccessSyncHost({required this.child});

  final Widget child;

  @override
  ConsumerState<_SmsAccessSyncHost> createState() => _SmsAccessSyncHostState();
}

class _SmsAccessSyncHostState extends ConsumerState<_SmsAccessSyncHost>
    with WidgetsBindingObserver {
  Future<void>? _syncInFlight;
  var _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPendingSms());
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
      _syncPendingSms();
    }
  }

  void _syncPendingSms() {
    if (_syncInFlight != null) return;
    final sync = _syncPendingSmsSafely();
    _syncInFlight = sync;
    unawaited(
      sync.whenComplete(() {
        if (identical(_syncInFlight, sync)) {
          _syncInFlight = null;
        }
      }),
    );
  }

  Future<void> _syncPendingSmsSafely() async {
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
      await ref.read(collectRepositoryProvider.notifier).syncPendingSmsAccess();
    } catch (_) {
      // SMS queue sync is retried on the next resume/realtime refresh.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
