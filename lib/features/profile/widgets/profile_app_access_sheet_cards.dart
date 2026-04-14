part of 'profile_app_access_sheet.dart';

class _SummaryCaption extends StatelessWidget {
  const _SummaryCaption({required this.readyCount, required this.totalCount});

  final int readyCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Text(
      context.l10n.profileAppAccessReadyCount(readyCount, totalCount),
      style: context.coolText.mono(
        Theme.of(context).textTheme.labelSmall,
        color: colors.secondaryText,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _AccessGroupCard extends StatelessWidget {
  const _AccessGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              const SizedBox(height: CoolSpace.x1),
          ],
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
    final isBlockedInSystem =
        settings.status.authorizationStatus == FcmAuthorizationStatus.denied;
    final colors = context.coolSemanticColors;
    final status = (
      label: settings.status.preferenceEnabled
          ? (settings.status.isAuthorized
                ? context.l10n.ready
                : context.l10n.profileNotificationsNeedsSystemAccess)
          : (isBlockedInSystem
                ? context.l10n.blockedInSystem
                : context.l10n.offInCool),
      color: settings.status.preferenceEnabled && settings.status.isAuthorized
          ? colors.accent
          : isBlockedInSystem
          ? colors.danger
          : settings.status.preferenceEnabled
          ? colors.warning
          : colors.secondaryText,
    );
    final canOpenSettings = isBlockedInSystem;

    return _AccessRowShell(
      icon: CoolIcons.notifications,
      title: context.l10n.notifications,
      subtitle: context.l10n.paymentAndActivityAlerts,
      statusLabel: status.label,
      statusColor: status.color,
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

    return _AccessRowShell(
      icon: metadata.icon,
      title: metadata.title,
      subtitle: metadata.subtitle,
      statusLabel: status.label,
      statusColor: status.color,
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
    );
  }
}

class _AccessRowShell extends StatelessWidget {
  const _AccessRowShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    required this.trailing,
    this.footerAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final Widget trailing;
  final Widget? footerAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x2),
                    _StatusIndicator(label: statusLabel, color: statusColor),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(padding: const EdgeInsets.only(top: 2), child: trailing),
            ],
          ),
          if (footerAction != null) ...[
            const SizedBox(height: CoolSpace.x3),
            Padding(
              padding: const EdgeInsets.only(left: 58),
              child: footerAction!,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(CoolRadii.pill),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
