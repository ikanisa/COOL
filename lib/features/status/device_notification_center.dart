part of 'device_privacy_screens.dart';

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
