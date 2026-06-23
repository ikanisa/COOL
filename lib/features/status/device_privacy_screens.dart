import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../core/notifications/collect_notification_service.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

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
              ? 'QR scan needs camera access. Group links still work.'
              : 'Payment reminders and security notices need alerts.',
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
              ? 'Allow camera access to scan group QR codes. You can still join by opening a valid group link.'
              : 'Allow notifications for payment reminders, group updates, and security notices.',
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

class PrivacyDataScreen extends StatelessWidget {
  const PrivacyDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Privacy and data',
      children: [
        const CollectVisualFeatureCard(
          asset: 'assets/brand/generated/collect_visual_qr_share.png',
          title: 'Private by default',
          message:
              'Public links use Collect IDs, safe amounts, group names, and payment status only.',
          icon: CollectIcons.privacy,
          tone: CollectStatusTone.privacy,
        ),
        const CollectBentoGrid(
          primary: BentoMetricCell(
            label: 'Public surfaces',
            value: 'Collect ID first.',
            detail: 'No private phone display',
            icon: CollectIcons.public,
            tone: CollectStatusTone.privacy,
            emphasis: true,
          ),
          top: BentoMetricCell(
            label: 'Payment data',
            value: 'Bounded',
            detail: 'Owner and support flows',
            icon: CollectIcons.momo,
            tone: CollectStatusTone.info,
          ),
          bottom: BentoMetricCell(
            label: 'Evidence',
            value: 'Protected',
            detail: 'SMS and ledger records',
            icon: CollectIcons.lock,
            tone: CollectStatusTone.success,
          ),
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.statusForeground(
            CollectStatusTone.privacy,
          ),
          child: const Column(
            children: [
              CollectListTile(
                leading: CollectIcons.public,
                title: 'Public group links',
                subtitle: 'Group name, QR, Collect IDs, and safe status only.',
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Collect ID first.',
                subtitle: 'Public group surfaces stay member-safe.',
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Private payment data',
                subtitle: 'Receiver numbers and support evidence stay bounded.',
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger records',
                subtitle:
                    'Retained where audit, dispute, or security needs it.',
              ),
            ],
          ),
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              const CollectListTile(
                leading: CollectIcons.profile,
                title: 'Member identity',
                subtitle: 'Public group activity uses Collect ID only.',
              ),
              const CollectListTile(
                leading: CollectIcons.momo,
                title: 'MoMo data',
                subtitle:
                    'Receiver numbers stay inside payment and owner flows.',
              ),
              const CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS evidence',
                subtitle: 'Used for payment matching and support review only.',
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Privacy policy',
                subtitle: 'Full data handling policy.',
                onTap: () => context.go('/settings/legal/privacy'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final latestContribution = state.contributions.isEmpty
        ? null
        : state.contributions.first;
    final pendingCount = state.paymentIntents
        .where((item) => item.status == 'pending')
        .length;
    final reviewCount = state.paymentIntents
        .where((item) => item.status == 'needs_review')
        .length;
    final permissionStatus = ref.watch(notificationPermissionStatusProvider);
    final notificationsGranted =
        permissionStatus == CollectDevicePermissionStatus.granted;
    final preferences = state.notificationPreferences;
    return ScreenScaffold(
      title: 'Notifications',
      showHeader: false,
      children: [
        const _NotificationPageHeader(),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: notificationsGranted
              ? context.collectColors.statusGranted
              : context.collectColors.statusBlocked,
          child: CollectListTile(
            leading: notificationsGranted
                ? CollectIcons.check
                : CollectIcons.pending,
            title: notificationsGranted
                ? 'Notifications enabled'
                : 'Notifications not enabled',
            trailing: CollectStatusChip(
              label: notificationsGranted ? 'On' : 'Off',
              tone: notificationsGranted
                  ? CollectStatusTone.success
                  : CollectStatusTone.warning,
              icon: notificationsGranted
                  ? CollectIcons.check
                  : CollectIcons.pending,
            ),
            onTap: () async {
              if (permissionStatus == CollectDevicePermissionStatus.denied) {
                await permissions.openAppSettings();
                return;
              }
              final granted = await _enableNativeNotifications(ref);
              final status = granted
                  ? CollectDevicePermissionStatus.granted
                  : CollectDevicePermissionStatus.denied;
              if (!context.mounted) return;
              ref.read(notificationPermissionStatusProvider.notifier).state =
                  status;
              if (status == CollectDevicePermissionStatus.denied) {
                context.go('/permissions/notifications-denied');
              }
            },
          ),
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              _NotificationPreferenceTile(
                icon: CollectIcons.money,
                title: 'Contribution confirmations',
                value: preferences.contributionConfirmations,
                onChanged: (value) => _saveNotificationPreference(
                  ref,
                  preferences.copyWith(contributionConfirmations: value),
                ),
              ),
              _NotificationPreferenceTile(
                icon: CollectIcons.pending,
                title: 'Payment reminders',
                value: preferences.paymentReminders,
                onChanged: (value) => _saveNotificationPreference(
                  ref,
                  preferences.copyWith(paymentReminders: value),
                ),
              ),
              _NotificationPreferenceTile(
                icon: CollectIcons.collections,
                title: 'Group updates',
                value: preferences.groupUpdates,
                onChanged: (value) => _saveNotificationPreference(
                  ref,
                  preferences.copyWith(groupUpdates: value),
                ),
              ),
              _NotificationPreferenceTile(
                icon: CollectIcons.warning,
                title: 'Security notices',
                value: preferences.securityNotices,
                onChanged: (value) => _saveNotificationPreference(
                  ref,
                  preferences.copyWith(securityNotices: value),
                ),
              ),
            ],
          ),
        ),
        if (state.contributions.isEmpty && pendingCount == 0)
          const MinimalStatePanel(
            icon: CollectIcons.pending,
            title: 'No updates yet.',
            message:
                'Contribution confirmations, pending payment reminders, and security notices will appear here.',
            tone: CollectStatusTone.neutral,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Today',
                actionLabel: pendingCount > 0 ? '$pendingCount pending' : null,
              ),
              CollectCard(
                emphasis: CollectCardEmphasis.flat,
                child: Column(
                  children: [
                    if (latestContribution != null)
                      NotificationUpdateRow(
                        title: 'Contribution confirmed',
                        message:
                            '${formatRwf(latestContribution.amountRwf)} was recorded on the ledger.',
                        meta: formatCollectDateTime(
                          latestContribution.createdAt,
                        ),
                        tone: CollectStatusTone.success,
                      ),
                    if (pendingCount > 0)
                      NotificationUpdateRow(
                        title: 'Payment verification pending',
                        message:
                            '$pendingCount payment${pendingCount == 1 ? '' : 's'} waiting for MoMo SMS verification.',
                        meta: 'Now',
                        tone: CollectStatusTone.info,
                      ),
                    if (reviewCount > 0)
                      NotificationUpdateRow(
                        title: 'Payment review',
                        message:
                            '$reviewCount payment${reviewCount == 1 ? '' : 's'} need support review.',
                        meta: 'Review',
                        tone: CollectStatusTone.warning,
                      ),
                    const NotificationUpdateRow(
                      title: 'Security notice',
                      message:
                          'Collect keeps receiver information inside payment and owner flows, not public share links.',
                      meta: 'Protected',
                      tone: CollectStatusTone.privacy,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _NotificationPageHeader extends StatelessWidget {
  const _NotificationPageHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Semantics(
      container: true,
      header: true,
      label: 'Notifications',
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Back',
            style: IconButton.styleFrom(
              backgroundColor: foreground.withValues(alpha: 0.10),
              foregroundColor: foreground,
              side: BorderSide(color: foreground.withValues(alpha: 0.16)),
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Text(
              'Notifications',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _saveNotificationPreference(
  WidgetRef ref,
  NotificationPreferences preferences,
) {
  return ref
      .read(collectRepositoryProvider.notifier)
      .updateNotificationPreferences(preferences);
}

Future<bool> _enableNativeNotifications(WidgetRef ref) async {
  final service = ref.read(collectNotificationServiceProvider);
  final granted = await service.requestPermission();
  if (!granted) return false;
  final repository = ref.read(collectRepositoryProvider.notifier);
  await service.registerDevice(repository);
  await service.showNotification(
    title: 'Collect notifications enabled',
    body:
        'Payment reminders, group updates, and security notices can now appear on this device.',
    payload: '/notifications',
  );
  return true;
}

class _NotificationPreferenceTile extends StatelessWidget {
  const _NotificationPreferenceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
      child: Row(
        children: [
          Icon(
            icon,
            color: value ? colors.statusGranted : colors.textMuted,
            size: 24,
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: colors.statusGranted,
            activeTrackColor: colors.statusGranted.withValues(alpha: 0.32),
            inactiveThumbColor: colors.textMuted,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'WhatsApp support',
      children: [
        CollectVisualFeatureCard(
          asset: 'assets/brand/generated/collect_visual_momo_signal.png',
          title: 'Support without secrets',
          message:
              'Collect support never needs MoMo PINs, OTPs, raw SMS, or private credentials.',
          icon: CollectIcons.support,
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'No PINs',
                subtitle: 'Never share payment credentials.',
              ),
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'No raw SMS',
                subtitle: 'Use support review flows.',
              ),
              CollectListTile(
                leading: CollectIcons.public,
                title: 'Support',
                subtitle: 'Share safe account context.',
              ),
            ],
          ),
        ),
        CollectButton(
          label: 'Open WhatsApp',
          icon: CollectIcons.support,
          onPressed: openCollectWhatsAppSupport,
          expand: true,
        ),
      ],
    );
  }
}
