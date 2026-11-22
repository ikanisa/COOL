import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/collect_notification_service.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';

class NotificationRegistrationHost extends ConsumerStatefulWidget {
  const NotificationRegistrationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationRegistrationHost> createState() =>
      NotificationRegistrationHostState();
}

class NotificationRegistrationHostState
    extends ConsumerState<NotificationRegistrationHost>
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
