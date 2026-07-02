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
                padding: const EdgeInsets.fromLTRB(
                  CollectSpacing.x4,
                  CollectSpacing.x2,
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
    unawaited(_syncPendingSmsSafely());
  }

  Future<void> _syncPendingSmsSafely() async {
    try {
      final env = ref.read(appEnvProvider);
      if (!env.enableAndroidSmsAccess && !env.enableSmsReader) return;
      final notifications = ref.read(collectNotificationServiceProvider);
      await notifications.initialize();
      final notificationsEnabled = await notifications
          .areNotificationsEnabled();
      ref
          .read(notificationPermissionStatusProvider.notifier)
          .state = notificationsEnabled
          ? CollectDevicePermissionStatus.granted
          : CollectDevicePermissionStatus.notRequested;
      await ref.read(collectRepositoryProvider.notifier).syncPendingSmsAccess();
    } catch (_) {
      // SMS queue sync is retried on the next resume/realtime refresh.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
