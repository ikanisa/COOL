import 'dart:async';

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
    message:
        'Collect uses Android SMS access only for owner-side MoMo payment matching when this internal build enables it.',
    tone: CollectStatusTone.warning,
    primaryLabel: 'Open app settings',
    primaryIcon: CollectIcons.settings,
    onPrimary: (sheetContext) {
      Navigator.of(sheetContext, rootNavigator: true).maybePop();
      permissions.openAppSettings();
    },
    secondaryLabel: 'Retry',
    secondaryIcon: CollectIcons.sync,
    onSecondary: (sheetContext) {
      Navigator.of(sheetContext, rootNavigator: true).maybePop();
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
    message:
        'Camera access lets Collect scan group QR codes without storing photos or gallery images.',
    tone: CollectStatusTone.warning,
    primaryLabel: 'Open app settings',
    primaryIcon: CollectIcons.settings,
    onPrimary: (sheetContext) {
      Navigator.of(sheetContext, rootNavigator: true).maybePop();
      permissions.openAppSettings();
    },
    secondaryLabel: 'Scan again',
    secondaryIcon: CollectIcons.qr,
    onSecondary: (sheetContext) {
      final navigator = Navigator.of(sheetContext, rootNavigator: true);
      unawaited(navigator.maybePop().then((_) => onRetry()));
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
    message:
        'Notifications keep payment reminders, group updates, and security notices visible when the app is closed.',
    tone: CollectStatusTone.info,
    primaryLabel: 'Enable',
    primaryIcon: CollectIcons.pending,
    onPrimary: (sheetContext) =>
        _requestNotificationsFromSheet(sheetContext, ref),
    secondaryLabel: 'Open app settings',
    secondaryIcon: CollectIcons.settings,
    onSecondary: (sheetContext) {
      Navigator.of(sheetContext, rootNavigator: true).maybePop();
      permissions.openAppSettings();
    },
  );
}

Future<void> _requestNotificationsFromSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final granted = await requestNativeNotifications(ref);
  if (!navigator.mounted) return;
  ref.read(notificationPermissionStatusProvider.notifier).state = granted
      ? CollectDevicePermissionStatus.granted
      : CollectDevicePermissionStatus.denied;
  await navigator.maybePop();
  if (granted || !navigator.mounted) return;
  await _showNotificationRecoverySheet(navigator.context, ref);
}

Future<void> _showNotificationRecoverySheet(
  BuildContext context,
  WidgetRef ref,
) {
  return _showNativeSettingsSheet(
    context,
    icon: CollectIcons.pending,
    title: 'Notifications',
    message:
        'Notification permission was not enabled. Try the phone prompt again or update Collect in app settings.',
    tone: CollectStatusTone.warning,
    primaryLabel: 'Try again',
    primaryIcon: CollectIcons.sync,
    onPrimary: (sheetContext) =>
        _requestNotificationsFromSheet(sheetContext, ref),
    secondaryLabel: 'Open app settings',
    secondaryIcon: CollectIcons.settings,
    onSecondary: (sheetContext) {
      Navigator.of(sheetContext, rootNavigator: true).maybePop();
      permissions.openAppSettings();
    },
  );
}

Future<bool> requestNativeNotifications(WidgetRef ref) async {
  final service = ref.read(collectNotificationServiceProvider);
  final granted = await service.requestPermission();
  if (!granted) return false;
  final repository = ref.read(collectRepositoryProvider.notifier);
  unawaited(service.registerDevice(repository));
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
  required String message,
  required CollectStatusTone tone,
  required String primaryLabel,
  required IconData primaryIcon,
  required ValueChanged<BuildContext> onPrimary,
  required String secondaryLabel,
  required IconData secondaryIcon,
  required ValueChanged<BuildContext> onSecondary,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: context.collectColors.transparent,
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          child: CollectBottomSheet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CollectPermissionEducationSheet(
                  icon: icon,
                  title: title,
                  message: 'Use native phone settings.',
                  education: message,
                  tone: tone,
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: primaryLabel,
                  icon: primaryIcon,
                  onPressed: () => onPrimary(sheetContext),
                  expand: true,
                ),
                CollectButton(
                  label: secondaryLabel,
                  icon: secondaryIcon,
                  onPressed: () => onSecondary(sheetContext),
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

class CollectPermissionEducationSheet extends StatelessWidget {
  const CollectPermissionEducationSheet({
    required this.icon,
    required this.title,
    required this.message,
    required this.education,
    this.tone = CollectStatusTone.warning,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String education;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MinimalStatePanel(
          icon: icon,
          title: title,
          message: message,
          tone: tone,
          messageMaxLines: 2,
        ),
        CollectSpacing.gap12,
        InfoSecurityBanner(
          title: 'Before you continue',
          message: education,
          tone: CollectStatusTone.info,
          messageMaxLines: 4,
        ),
      ],
    );
  }
}
