part of 'profile_settings_widgets.dart';

class ProfileSectionToggleCard extends StatelessWidget {
  const ProfileSectionToggleCard({
    required this.title,
    required this.subtitle,
    required this.isExpanded,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Semantics(
      button: true,
      label:
          '$title. $subtitle. ${isExpanded ? context.l10n.profileSectionExpanded : context.l10n.profileSectionCollapsed}',
      hint: isExpanded
          ? context.l10n.profileCollapseSection
          : context.l10n.profileExpandSection,
      child: ExcludeSemantics(
        child: CoolCard(
          backgroundColor: colors.cardSurface,
          onTap: onTap,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: colors.secondaryText,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileDangerZone extends StatelessWidget {
  const ProfileDangerZone({
    required this.onDeleteAccount,
    required this.onSignOut,
    super.key,
  });

  final VoidCallback onDeleteAccount;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final l10n = context.l10n;
    return ProfileSettingsSection(
      title: l10n.accountActionsTitle,
      rows: [
        ProfileSettingsRow(
          icon: Icons.logout_rounded,
          label: l10n.signOutAction,
          onTap: onSignOut,
        ),
        ProfileSettingsRow(
          icon: Icons.delete_outline_rounded,
          iconColor: colors.danger,
          label: l10n.deleteAccountAction,
          labelColor: colors.danger,
          onTap: onDeleteAccount,
          showArrow: false,
        ),
      ],
    );
  }
}

class ProfileNotificationToggle extends StatelessWidget {
  const ProfileNotificationToggle({
    required this.value,
    required this.onChanged,
    this.isLoading = false,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Semantics(
      label: context.l10n.notificationsLabel,
      toggled: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CupertinoActivityIndicator(radius: 8),
            ),
            const SizedBox(width: 8),
          ],
          Switch.adaptive(
            value: value,
            onChanged: isLoading ? null : onChanged,
            activeTrackColor: colors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
