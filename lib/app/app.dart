import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/collect_notification_service.dart';
import '../shared/providers/collect_app_state.dart';
import '../shared/repositories/collect_repository.dart';
import '../shared/widgets/collect_components.dart';
import 'env/app_env.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/collect_theme_controller.dart';

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
    );
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
    if (state == AppLifecycleState.resumed) {
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
      final env = ref.read(appEnvProvider);
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
      if (!env.enableAndroidSmsAccess && !env.enableSmsReader) return;
      await ref.read(collectRepositoryProvider.notifier).syncPendingSmsAccess();
    } catch (_) {
      // SMS queue sync is retried on the next resume/realtime refresh.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
