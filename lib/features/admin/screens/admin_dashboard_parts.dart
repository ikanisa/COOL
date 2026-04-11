part of 'admin_dashboard_screen.dart';

EdgeInsets _adminRoleBadgePadding() => CoolSpace.denseSectionPadding.copyWith(
  left: CoolSpace.x3,
  right: CoolSpace.x3,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

class _RoleBadgeRow extends StatelessWidget {
  const _RoleBadgeRow({required this.access});

  final AdminWorkspaceAccess access;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final badges = <_RoleBadge>[
      if (access.hasPlatformAccess)
        _RoleBadge(context.l10n.platformAdmin, colors.success),
    ];

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: CoolSpace.x3,
      runSpacing: CoolSpace.x2,
      children: badges,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: _adminRoleBadgePadding(),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
      ),
      child: Text(
        label.toUpperCase(),
        style: context.coolText.mono(
          theme.textTheme.labelMedium,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.section});

  final AdminWorkspaceDestination section;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      padding: CoolSpace.sectionPadding,
      backgroundColor: colors.cardSurfaceStrong,
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(section.route);
      },
      semanticsLabel: '${section.title}. ${section.subtitle}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.operationalSurface,
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.md),
              ),
              boxShadow: CoolShadows.ambientFloat(strength: 0.15),
            ),
            child: Icon(section.icon, size: 22, color: colors.primaryText),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            section.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.coolText.display(
              theme.textTheme.titleSmall,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Expanded(
            child: Text(
              section.subtitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.coolText.mobiLabel(
                color: colors.tertiaryText,
              ).copyWith(
                fontWeight: FontWeight.w400,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
