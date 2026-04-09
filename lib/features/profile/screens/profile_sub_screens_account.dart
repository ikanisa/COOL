part of 'profile_sub_screens.dart';

class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewProvider);
    final colors = context.coolSemanticColors;
    final memberSince = profile.createdAt != null
        ? '${profile.createdAt!.day}/${profile.createdAt!.month}/${profile.createdAt!.year}'
        : 'UNKNOWN';

    return _ProfileSubScaffold(
      title: 'ACCOUNT',
      subtitle: 'PERSONAL INFORMATION',
      icon: Icons.person_outline_rounded,
      slivers: [
        const _SectionLabel(label: 'IDENTITY'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.accent, colors.info],
                      ),
                      borderRadius: BorderRadius.circular(CoolRadii.lg),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.initials,
                      style: context.coolText.displayCondensed(
                        Theme.of(context).textTheme.headlineMedium,
                        fontWeight: FontWeight.w900,
                        color: colors.accentForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name.isNotEmpty
                              ? profile.name.toUpperCase()
                              : 'ANONYMOUS FAN',
                          style: context.coolText.displayCondensed(
                            Theme.of(context).textTheme.titleLarge,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'MEMBER SINCE $memberSince',
                          style: context.coolText.mono(
                            Theme.of(context).textTheme.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.badge_outlined,
                title: 'MEMBER ID',
                value: profile.userId.isNotEmpty ? profile.userId : '------',
              ),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.phone_outlined,
                title: 'PHONE',
                value: profile.phone.isNotEmpty ? profile.phone : 'NOT SET',
              ),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.flag_outlined,
                title: 'COUNTRY',
                value: profile.country.toUpperCase(),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),
        const _SectionLabel(label: 'PAYMENTS'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.account_balance_wallet_outlined,
                title: 'PAYMENT STATUS',
                value: profile.momoLinked ? 'LINKED' : 'NOT LINKED',
                valueColor: profile.momoLinked
                    ? colors.success
                    : colors.secondaryText,
              ),
              if (profile.momoLinked) ...[
                const _RowDivider(),
                _InfoRow(
                  icon: Icons.phone_android_outlined,
                  title: 'RECEIVE ROUTE',
                  value: profile.momoDisplayLabel,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifState = ref.watch(notificationSettingsProvider);
    final profile = ref.watch(profileViewProvider);
    final colors = context.coolSemanticColors;
    final topicPreferences = notifState.status.topicPreferences;

    return _ProfileSubScaffold(
      title: 'NOTIFICATIONS',
      subtitle: 'ALERTS & UPDATES',
      icon: Icons.notifications_none_rounded,
      slivers: [
        const _SectionLabel(label: 'PUSH NOTIFICATIONS'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              _ToggleRow(
                icon: Icons.notifications_active_outlined,
                title: 'ALL NOTIFICATIONS',
                subtitle: 'MASTER TOGGLE',
                value: profile.notificationsEnabled,
                isLoading: notifState.isLoading,
                onChanged: (value) => ref
                    .read(notificationSettingsProvider.notifier)
                    .setEnabled(value),
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.sports_soccer_outlined,
                title: 'MATCH ALERTS',
                subtitle: 'KICKOFF & RESULTS',
                value: topicPreferences[FcmTopicCategory.matchAlerts] ?? true,
                isLoading: notifState.isLoading,
                onChanged: (value) => ref
                    .read(notificationSettingsProvider.notifier)
                    .setTopicEnabled(FcmTopicCategory.matchAlerts, value),
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.local_offer_outlined,
                title: 'PROMOTIONS',
                subtitle: 'SHOP & MEMBERSHIP',
                value: topicPreferences[FcmTopicCategory.promotions] ?? true,
                isLoading: notifState.isLoading,
                onChanged: (value) => ref
                    .read(notificationSettingsProvider.notifier)
                    .setTopicEnabled(FcmTopicCategory.promotions, value),
              ),
              const _RowDivider(),
              _ToggleRow(
                icon: Icons.groups_outlined,
                title: 'GROUP UPDATES',
                subtitle: 'CONTRIBUTIONS & INVITES',
                value: topicPreferences[FcmTopicCategory.groupUpdates] ?? true,
                isLoading: notifState.isLoading,
                onChanged: (value) => ref
                    .read(notificationSettingsProvider.notifier)
                    .setTopicEnabled(FcmTopicCategory.groupUpdates, value),
              ),
            ],
          ),
        ),
        if (notifState.error != null) ...[
          const SizedBox(height: CoolSpace.x3),
          Container(
            padding: const EdgeInsets.all(CoolSpace.x4),
            decoration: BoxDecoration(
              color: colors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(CoolRadii.lg),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: colors.danger,
                  size: 20,
                ),
                const SizedBox(width: CoolSpace.x3),
                Expanded(
                  child: Text(
                    notifState.error!,
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: colors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
