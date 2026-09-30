import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../core/notifications/collect_notification_service.dart';
import '../../core/security/sms_access_channel.dart';
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
        'This separately signed operations build uses Android SMS access only for new MoMo receipt messages after you opt in. It does not read inbox history or unrelated SMS.',
    tone: CollectStatusTone.warning,
    primaryLabel: 'Open app settings',
    primaryIcon: CollectIcons.settings,
    onPrimary: (sheetContext) {
      Navigator.of(sheetContext, rootNavigator: true).maybePop();
      unawaited(const SmsAccessChannel().openAppSettings());
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
        'Notifications keep contribution reminders, group updates, and security notices visible when the app is closed.',
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
  final service = ref.read(collectNotificationServiceProvider);
  final fence = service.registrationContext;
  final connected = await requestNativeNotifications(ref);
  if (!context.mounted ||
      !navigator.mounted ||
      !service.isRegistrationContextCurrent(fence)) {
    return;
  }
  ref
      .read(notificationPermissionStatusProvider.notifier)
      .state = switch (service.permissionGranted) {
    true => CollectDevicePermissionStatus.granted,
    false => CollectDevicePermissionStatus.denied,
    null => CollectDevicePermissionStatus.notRequested,
  };
  await navigator.maybePop();
  if (connected ||
      !navigator.mounted ||
      !service.isRegistrationContextCurrent(fence)) {
    return;
  }
  await _showNotificationRecoverySheet(navigator.context, ref);
}

Future<void> _showNotificationRecoverySheet(
  BuildContext context,
  WidgetRef ref,
) {
  final status = ref
      .read(collectNotificationServiceProvider)
      .registrationStatus
      .value;
  final requiresLogin = status == CollectNotificationStatus.signInRequired;
  return _showNativeSettingsSheet(
    context,
    icon: CollectIcons.pending,
    title: 'Notifications',
    message: status.message,
    tone: CollectStatusTone.warning,
    primaryLabel: requiresLogin ? 'Sign in again' : 'Try again',
    primaryIcon: CollectIcons.sync,
    onPrimary: (sheetContext) => requiresLogin
        ? signInForNotifications(sheetContext, ref)
        : _requestNotificationsFromSheet(sheetContext, ref),
    secondaryLabel: 'Open app settings',
    secondaryIcon: CollectIcons.settings,
    onSecondary: (sheetContext) {
      Navigator.of(sheetContext, rootNavigator: true).maybePop();
      permissions.openAppSettings();
    },
  );
}

Future<void> signInForNotifications(BuildContext context, WidgetRef ref) async {
  final repository = ref.read(collectRepositoryProvider.notifier);
  final service = ref.read(collectNotificationServiceProvider);
  final fence = service.registrationContext;
  try {
    await repository.signOut();
    if (context.mounted && !repository.isLive) context.go('/auth');
  } catch (_) {
    if (context.mounted &&
        repository.isLive &&
        service.isRegistrationContextCurrent(fence)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Try again.')),
      );
    }
  }
}

Future<bool> requestNativeNotifications(WidgetRef ref) async {
  final service = ref.read(collectNotificationServiceProvider);
  final repository = ref.read(collectRepositoryProvider.notifier);
  // Phone permission alone never establishes a notification connection.
  return service.enableDevice(repository);
}

Future<void> _showNativeSettingsSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required CollectStatusTone tone,
  required String primaryLabel,
  required IconData primaryIcon,
  required FutureOr<void> Function(BuildContext) onPrimary,
  required String secondaryLabel,
  required IconData secondaryIcon,
  required ValueChanged<BuildContext> onSecondary,
}) {
  var submitting = false;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: context.collectColors.transparent,
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            CollectSpacing.x4,
            CollectSpacing.x4,
            CollectSpacing.x4,
            MediaQuery.viewInsetsOf(sheetContext).bottom +
                MediaQuery.paddingOf(sheetContext).bottom +
                CollectSpacing.x4,
          ),
          child: SingleChildScrollView(
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
                    onPressed: submitting
                        ? null
                        : () async {
                            setSheetState(() => submitting = true);
                            try {
                              await onPrimary(sheetContext);
                            } finally {
                              if (sheetContext.mounted) {
                                setSheetState(() => submitting = false);
                              }
                            }
                          },
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
    ),
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
        Text(
          education,
          style: Theme.of(context).textTheme.bodyMedium,
          softWrap: true,
        ),
      ],
    );
  }
}
