part of 'device_privacy_screens.dart';

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final preferences = state.notificationPreferences;
    final events = state.notificationEvents;
    final unreadCount = events.where((event) => event.unread).length;
    return ScreenScaffold(
      title: 'Notifications',
      showHeader: false,
      children: [
        const _NotificationPageHeader(),
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
        if (events.isEmpty)
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
                actionLabel: unreadCount > 0 ? '$unreadCount pending' : null,
              ),
              CollectCard(
                emphasis: CollectCardEmphasis.flat,
                child: Column(
                  children: [
                    for (final event in events)
                      NotificationUpdateRow(
                        title: event.title,
                        message: event.body,
                        meta: _notificationMeta(event),
                        tone: _notificationTone(event.type),
                        onTap: event.unread
                            ? () => _markNotificationRead(ref, event.id)
                            : null,
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

CollectStatusTone _notificationTone(String type) {
  return switch (type) {
    'contribution_confirmed' => CollectStatusTone.success,
    'payment_reminder' => CollectStatusTone.info,
    'security_notice' => CollectStatusTone.privacy,
    'payment_review' => CollectStatusTone.warning,
    _ => CollectStatusTone.info,
  };
}

String _notificationMeta(NotificationEvent event) {
  if (event.status == 'read') return 'Read';
  if (event.status == 'queued') return 'Pending';
  return formatCollectDateTime(event.createdAt);
}

Future<void> _markNotificationRead(WidgetRef ref, String eventId) {
  return ref
      .read(collectRepositoryProvider.notifier)
      .markNotificationRead(eventId);
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
