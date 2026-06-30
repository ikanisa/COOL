import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../core/notifications/collect_notification_service.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';

Future<void> showSmsAccessSheet(
  BuildContext context, {
  required VoidCallback onRetry,
}) {
  return _showNativeSettingsSheet(
    context,
    icon: CollectIcons.sms,
    title: 'SMS access',
    tone: CollectStatusTone.warning,
    primaryLabel: 'Open app settings',
    primaryIcon: CollectIcons.settings,
    onPrimary: () {
      Navigator.of(context).maybePop();
      permissions.openAppSettings();
    },
    secondaryLabel: 'Retry',
    secondaryIcon: CollectIcons.sync,
    onSecondary: () {
      Navigator.of(context).maybePop();
      onRetry();
    },
  );
}

Future<void> showCameraAccessSheet(
  BuildContext context, {
  required VoidCallback onRetry,
}) {
  return _showNativeSettingsSheet(
    context,
    icon: CollectIcons.qr,
    title: 'Camera access',
    tone: CollectStatusTone.warning,
    primaryLabel: 'Open app settings',
    primaryIcon: CollectIcons.settings,
    onPrimary: () {
      Navigator.of(context).maybePop();
      permissions.openAppSettings();
    },
    secondaryLabel: 'Scan again',
    secondaryIcon: CollectIcons.qr,
    onSecondary: () {
      Navigator.of(context).maybePop();
      onRetry();
    },
  );
}

Future<void> showNotificationSettingsSheet(
  BuildContext context,
  WidgetRef ref,
) {
  return _showNativeSettingsSheet(
    context,
    icon: CollectIcons.pending,
    title: 'Notifications',
    tone: CollectStatusTone.info,
    primaryLabel: 'Enable',
    primaryIcon: CollectIcons.pending,
    onPrimary: () async {
      final granted = await requestNativeNotifications(ref);
      if (!context.mounted) return;
      ref.read(notificationPermissionStatusProvider.notifier).state = granted
          ? CollectDevicePermissionStatus.granted
          : CollectDevicePermissionStatus.denied;
      Navigator.of(context).maybePop();
      if (!granted) permissions.openAppSettings();
    },
    secondaryLabel: 'Open app settings',
    secondaryIcon: CollectIcons.settings,
    onSecondary: () {
      Navigator.of(context).maybePop();
      permissions.openAppSettings();
    },
  );
}

Future<bool> requestNativeNotifications(WidgetRef ref) async {
  final service = ref.read(collectNotificationServiceProvider);
  final granted = await service.requestPermission();
  if (!granted) return false;
  final repository = ref.read(collectRepositoryProvider.notifier);
  await service.registerDevice(repository);
  await service.showNotification(
    title: 'Collect notifications enabled',
    body: 'Payment reminders, group updates, and security notices are enabled.',
    payload: '/home',
  );
  return true;
}

Future<void> _showNativeSettingsSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required CollectStatusTone tone,
  required String primaryLabel,
  required IconData primaryIcon,
  required VoidCallback onPrimary,
  required String secondaryLabel,
  required IconData secondaryIcon,
  required VoidCallback onSecondary,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.collectColors.transparent,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          child: CollectBottomSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MinimalStatePanel(
                  icon: icon,
                  title: title,
                  message: 'Use native phone settings.',
                  tone: tone,
                  messageMaxLines: 1,
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: primaryLabel,
                  icon: primaryIcon,
                  onPressed: onPrimary,
                  expand: true,
                ),
                CollectButton(
                  label: secondaryLabel,
                  icon: secondaryIcon,
                  onPressed: onSecondary,
                  variant: CollectButtonVariant.secondary,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
