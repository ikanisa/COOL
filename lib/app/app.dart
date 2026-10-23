import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/collect_notification_service.dart';
import '../core/security/sms_access_channel.dart';
import '../core/cloudflare/cloudflare_module.dart';
import '../l10n/collect_localizations.dart';
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

    return _PendingSharedGroupIntentRecoveryHost(
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
              supportedLocales: CollectLocalizations.supportedLocales,
              localizationsDelegates: const [
                CollectLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              locale: const Locale('en'),
              routerConfig: router,
              builder: (context, child) {
                final dark = Theme.of(context).brightness == Brightness.dark;
                final icons = dark ? Brightness.light : Brightness.dark;
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: CollectColors.transparentColor,
                    statusBarIconBrightness: icons,
                    statusBarBrightness: dark
                        ? Brightness.dark
                        : Brightness.light,
                    systemNavigationBarColor: context.collectColors.canvas,
                    systemNavigationBarIconBrightness: icons,
                    systemNavigationBarDividerColor:
                        CollectColors.transparentColor,
                  ),
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
  static const _retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
  StreamSubscription<void>? _subscription;
  Future<int>? _syncInFlight;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _syncRequested = false;
  bool _foreground = true;
  late final bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled =
        ref.read(appEnvProvider).enableAndroidSmsAccess &&
        ref.read(momoReceiptCaptureAvailableProvider);
    if (!_enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _subscription = const SmsAccessChannel().pendingSmsEvents.listen(
      (_) => _sync(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    if (_enabled) WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _retryTimer?.cancel();
      _retryTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _sync();
    }
  }

  void _sync({bool newSignal = true}) {
    if (!_enabled || !_foreground || !mounted) return;
    if (newSignal) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryAttempt = 0;
    }
    if (_syncInFlight != null) {
      _syncRequested = true;
      return;
    }
    final owner = ref.read(collectRepositoryProvider).currentProfile?.id;
    final sync = ref
        .read(collectRepositoryProvider.notifier)
        .syncPendingSmsAccess();
    _syncInFlight = sync;
    unawaited(
      sync.then<void>(
        (_) => _finishSync(sync, owner, failed: false),
        onError: (Object _, StackTrace _) =>
            _finishSync(sync, owner, failed: true),
      ),
    );
  }

  void _finishSync(Future<int> sync, String? owner, {required bool failed}) {
    if (!identical(_syncInFlight, sync)) return;
    _syncInFlight = null;
    if (!mounted || !_enabled) return;
    final currentOwner = ref.read(collectRepositoryProvider).currentProfile?.id;
    if (currentOwner != owner) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryAttempt = 0;
      _syncRequested = false;
      if (currentOwner != null) _sync();
      return;
    }
    if (_syncRequested) {
      _syncRequested = false;
      _sync();
      return;
    }
    if (!failed) {
      _retryAttempt = 0;
      return;
    }
    if (!_foreground || currentOwner == null) return;
    // A single foreground timer retries without persisting an auth token or
    // continuously waking a background process. Delay is capped at 15 minutes.
    final index = _retryAttempt < _retryDelays.length
        ? _retryAttempt
        : _retryDelays.length - 1;
    if (_retryAttempt < _retryDelays.length) _retryAttempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelays[index], () {
      _retryTimer = null;
      _sync(newSignal: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled) {
      ref.listen<String?>(
        collectRepositoryProvider.select((state) => state.currentProfile?.id),
        (_, current) {
          if (current == null) {
            _retryTimer?.cancel();
            _retryTimer = null;
            _retryAttempt = 0;
            _syncRequested = false;
          } else {
            _sync();
          }
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
    final client = ref.read(collectBackendClientProvider);
    final owner = client == null
        ? ref.read(collectAuthenticatedUserIdProvider)
        : client.auth.currentUser?.id;
    if (intent.recipientId != null && intent.recipientId != owner) {
      return;
    }
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
          await ref
              .read(pendingSharedGroupSlugProvider.notifier)
              .retainIncomingRecord(
                slug,
                ownerUserId: ref.read(collectAuthenticatedUserIdProvider),
              );
          if (!mounted) return;
          _scheduleNavigation('/c/${Uri.encodeComponent(slug)}');
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
    try {
      final pendingIntent = ref.read(pendingSharedGroupSlugProvider.notifier);
      final ownerId = ref.read(collectAuthenticatedUserIdProvider);
      if (ownerId == null) return;
      final intent = await pendingIntent.currentRecordForOwner(ownerId);
      if (!mounted || intent == null) return;
      final readiness = ref.read(profileReadinessProvider);
      if (!readiness.readyForGroupCreation) return;

      final router = ref.read(appRouterProvider);
      final intentPath = '/c/${Uri.encodeComponent(intent.slug)}';
      if (router.routeInformationProvider.value.uri.path == intentPath) return;
      _scheduleNavigation(intentPath);
    } catch (_) {
      // Local persistence can fail while binding or clearing a pending link.
      // A link must never navigate from a record that could not be verified.
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
      } else if (permissionState == CollectDevicePermissionStatus.granted) {
        // A previously granted permission becoming disabled is a denial.
        // Preserve both the initial not-requested state and an explicit denial:
        // Android's resumed callback can race the result of the native prompt.
        ref.read(notificationPermissionStatusProvider.notifier).state =
            CollectDevicePermissionStatus.denied;
      }
      // The service checks permission and publishes registration recovery even
      // when a previously allowed permission was revoked in phone settings.
      final repository = ref.read(collectRepositoryProvider.notifier);
      if (repository.isLive) {
        unawaited(notifications.registerDevice(repository));
      }
    } catch (_) {
      // Device notification registration is retried on the next resume.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
