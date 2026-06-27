part of 'device_privacy_screens.dart';

class PermissionRecoveryScreen extends ConsumerWidget {
  const PermissionRecoveryScreen({required this.kind, super.key});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCamera = kind == 'camera';
    final title = isCamera ? 'Camera access' : 'Notifications';
    return ScreenScaffold(
      title: title,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: isCamera ? 'Try scan again' : 'Enable notifications',
            icon: isCamera ? CollectIcons.qr : CollectIcons.pending,
            onPressed: () async {
              if (isCamera) {
                final opened = await permissions.openAppSettings();
                if (!opened || !context.mounted) return;
                context.go('/groups/scan');
              } else {
                final granted = await _enableNativeNotifications(ref);
                if (!context.mounted) return;
                ref
                    .read(notificationPermissionStatusProvider.notifier)
                    .state = granted
                    ? CollectDevicePermissionStatus.granted
                    : CollectDevicePermissionStatus.denied;
                context.go(
                  granted
                      ? '/permissions/device'
                      : '/permissions/notifications-denied',
                );
              }
            },
            expand: true,
          ),
          const CollectButton(
            label: 'App settings',
            icon: CollectIcons.settings,
            onPressed: permissions.openAppSettings,
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: [
        CollectVisualFeatureCard(
          asset: isCamera
              ? 'assets/brand/generated/collect_visual_qr_share.png'
              : 'assets/brand/generated/collect_visual_momo_signal.png',
          icon: isCamera ? CollectIcons.qr : CollectIcons.pending,
          title: isCamera ? 'Camera blocked' : 'Alerts blocked',
          message: isCamera
              ? 'Scan QR codes or use a group link.'
              : 'Turn on payment and security alerts.',
          tone: isCamera ? CollectStatusTone.info : CollectStatusTone.warning,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: isCamera ? CollectIcons.qr : CollectIcons.pending,
                title: isCamera ? 'Scan route' : 'Alert route',
                subtitle: isCamera ? 'Camera-first QR join.' : 'Device alerts.',
                trailing: const CollectStatusChip(
                  label: 'Blocked',
                  tone: CollectStatusTone.warning,
                  icon: CollectIcons.warning,
                ),
              ),
              const CollectListTile(
                leading: CollectIcons.settings,
                title: 'App settings',
                subtitle: 'Restore access in the OS.',
                trailing: Icon(CollectIcons.chevron),
                onTap: permissions.openAppSettings,
              ),
            ],
          ),
        ),
        CollectPermissionRecoveryPanel(
          icon: isCamera ? CollectIcons.qr : CollectIcons.pending,
          title: isCamera
              ? 'Camera permission was blocked.'
              : 'Notification permission was blocked.',
          message: isCamera
              ? 'Allow camera access for QR scan.'
              : 'Allow notifications for payment updates.',
          settingsMessage: isCamera
              ? 'Open app settings if the OS keeps blocking camera access.'
              : 'Open app settings if notification permission remains denied.',
        ),
      ],
    );
  }
}

class NotificationPermissionScreen extends ConsumerWidget {
  const NotificationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final smsStatus = ref.watch(smsPermissionStatusProvider);
    final smsGranted = smsStatus == SmsPermissionStatus.granted;
    final showSmsAccess = _supportsAndroidSmsAccess;
    final notificationStatus = ref.watch(notificationPermissionStatusProvider);
    final notificationGranted =
        notificationStatus == CollectDevicePermissionStatus.granted;
    return ScreenScaffold(
      title: 'App access',
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: 'Done',
            icon: CollectIcons.check,
            onPressed: () => goBackOrHome(context),
            expand: true,
          ),
        ],
      ),
      children: [
        const _DeviceAccessPageHeader(),
        if (showSmsAccess)
          _PermissionSettingRow(
            icon: CollectIcons.sms,
            title: 'SMS access',
            status: smsGranted
                ? 'Allowed'
                : smsStatus == SmsPermissionStatus.denied
                ? 'Denied'
                : 'Action-triggered',
            active: smsGranted,
            onTap: () => context.go('/groups/create'),
          ),
        _PermissionSettingRow(
          icon: CollectIcons.pending,
          title: 'Notifications',
          status: notificationGranted
              ? 'Allowed'
              : notificationStatus == CollectDevicePermissionStatus.denied
              ? 'Denied'
              : 'Action-triggered',
          active: notificationGranted,
          onTap: () => context.go('/notifications'),
        ),
        _PermissionSettingRow(
          icon: CollectIcons.privacy,
          title: 'Privacy',
          status: 'Protected',
          active: true,
          onTap: () => context.go('/settings/legal/privacy'),
        ),
      ],
    );
  }
}

class _DeviceAccessPageHeader extends StatelessWidget {
  const _DeviceAccessPageHeader();

  @override
  Widget build(BuildContext context) {
    return const CollectPlainPageHeader(title: 'App access');
  }
}

bool get _supportsAndroidSmsAccess {
  return kIsWeb || defaultTargetPlatform == TargetPlatform.android;
}

class _PermissionSettingRow extends StatelessWidget {
  const _PermissionSettingRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String status;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = active ? CollectStatusTone.success : CollectStatusTone.warning;
    return CollectListTile(
      leading: icon,
      title: title,
      subtitle: status,
      trailing: CollectStatusChip(
        label: status,
        tone: tone,
        icon: active ? CollectIcons.check : CollectIcons.pending,
      ),
      onTap: onTap,
    );
  }
}
