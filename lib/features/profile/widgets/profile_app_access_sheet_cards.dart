part of 'profile_app_access_sheet.dart';

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.readyCount, required this.totalCount});

  final int readyCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.15),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.chipSelectedBackground,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            child: Icon(
              Icons.admin_panel_settings_outlined,
              color: colors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$readyCount/$totalCount ready',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  'All access controls',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationAccessCard extends StatelessWidget {
  const _NotificationAccessCard({
    required this.settings,
    required this.onChanged,
    required this.onOpenSettings,
  });

  final NotificationSettingsState settings;
  final ValueChanged<bool> onChanged;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isBlockedInSystem =
        settings.status.authorizationStatus == FcmAuthorizationStatus.denied;
    final statusLabel = settings.status.preferenceEnabled
        ? (settings.status.isAuthorized ? 'Ready' : 'Needs system access')
        : (isBlockedInSystem ? 'Blocked in system' : 'Off in COOL');
    final statusColor =
        settings.status.preferenceEnabled && settings.status.isAuthorized
        ? colors.accent
        : isBlockedInSystem
        ? colors.danger
        : settings.status.preferenceEnabled
        ? colors.warning
        : colors.secondaryText;
    final canOpenSettings = isBlockedInSystem;

    return _AccessCardShell(
      icon: Icons.notifications_outlined,
      title: context.l10n.notifications,
      subtitle: context.l10n.paymentAndActivityAlerts,
      statusLabel: statusLabel,
      statusColor: statusColor,
      linkedFeatures: const [
        'MoMo updates',
        'Groups activity',
        'Service updates',
        'Partner announcements',
      ],
      trailing: ProfileNotificationToggle(
        value: settings.status.preferenceEnabled,
        onChanged: onChanged,
        isLoading: settings.isLoading,
      ),
      footerAction: canOpenSettings
          ? _InlineActionButton(
              label: context.l10n.openSystemSettings,
              onTap: () => onOpenSettings(),
            )
          : null,
      helperText: isBlockedInSystem
          ? 'Blocked in system'
          : settings.status.preferenceEnabled
          ? 'Enabled'
          : 'Disabled',
    );
  }
}

class _PermissionAccessCard extends StatelessWidget {
  const _PermissionAccessCard({
    required this.metadata,
    required this.snapshot,
    required this.isBusy,
    required this.onChanged,
    required this.onOpenSettings,
  });

  final _PermissionMetadata metadata;
  final AppAccessSnapshot snapshot;
  final bool isBusy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final status = _statusFor(context, snapshot);
    final footerAction = switch (snapshot.kind) {
      AppAccessStateKind.blockedInSystem => _InlineActionButton(
        label: context.l10n.openSystemSettings,
        onTap: onOpenSettings,
      ),
      AppAccessStateKind.serviceDisabled => _InlineActionButton(
        label: metadata.serviceActionLabel,
        onTap: onOpenSettings,
      ),
      AppAccessStateKind.notAvailable => null,
      _ => null,
    };

    return _AccessCardShell(
      icon: metadata.icon,
      title: metadata.title,
      subtitle: metadata.subtitle,
      statusLabel: status.label,
      statusColor: status.color,
      linkedFeatures: metadata.linkedFeatures,
      trailing: isBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CupertinoActivityIndicator(radius: 12),
            )
          : Switch.adaptive(
              value: snapshot.enabledInApp,
              onChanged: snapshot.kind == AppAccessStateKind.notAvailable
                  ? null
                  : onChanged,
              activeTrackColor: colors.accent,
            ),
      footerAction: footerAction,
      helperText: _helperText(snapshot),
    );
  }
}

class _AccessCardShell extends StatelessWidget {
  const _AccessCardShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    required this.linkedFeatures,
    required this.trailing,
    required this.helperText,
    this.footerAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final List<String> linkedFeatures;
  final Widget trailing;
  final Widget? footerAction;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final colors = context.coolSemanticColors;
        final isNarrow = constraints.maxWidth < 380;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(CoolRadii.xl),
            boxShadow: CoolShadows.ambientFloat(strength: 0.15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.inputSurface,
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: colors.primaryText, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isNarrow) ...[
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: CoolSpace.x2),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _StatusPill(
                                label: statusLabel,
                                color: statusColor,
                              ),
                              trailing,
                            ],
                          ),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colors.primaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusPill(
                                label: statusLabel,
                                color: statusColor,
                              ),
                            ],
                          ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w400,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isNarrow) ...[const SizedBox(width: 12), trailing],
                ],
              ),
              const SizedBox(height: CoolSpace.x3),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: linkedFeatures
                    .map(
                      (feature) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colors.chipBackground,
                          borderRadius: BorderRadius.circular(CoolRadii.pill),
                          boxShadow: CoolShadows.ambientFloat(strength: 0.15),
                        ),
                        child: Text(
                          feature,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: CoolSpace.x3),
              Text(
                helperText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.tertiaryText,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                ),
              ),
              if (footerAction != null) ...[
                const SizedBox(height: CoolSpace.x3),
                footerAction!,
              ],
            ],
          ),
        );
      },
    );
  }
}
