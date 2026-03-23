part of '../screens/schedule_trip_screen.dart';

class _ScheduleTripRoleSheet extends StatelessWidget {
  const _ScheduleTripRoleSheet({
    required this.selectedRole,
    required this.canScheduleAsDriver,
  });

  final ScheduleTripPostingRole selectedRole;
  final bool canScheduleAsDriver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CoolRadii.xxl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Choose role',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              _ScheduleTripRoleSheetOption(
                label: context.l10n.passenger,
                subtitle: context.l10n.defaultMode,
                selected: selectedRole == ScheduleTripPostingRole.passenger,
                onTap: () => Navigator.of(
                  context,
                ).pop(ScheduleTripPostingRole.passenger),
              ),
              Divider(color: colors.divider),
              _ScheduleTripRoleSheetOption(
                label: context.l10n.driver,
                subtitle: canScheduleAsDriver
                    ? 'Post as driver'
                    : 'Setup required',
                selected: selectedRole == ScheduleTripPostingRole.driver,
                onTap: () =>
                    Navigator.of(context).pop(ScheduleTripPostingRole.driver),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleTripRoleSheetOption extends StatelessWidget {
  const _ScheduleTripRoleSheetOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return ListTile(
      minTileHeight: CoolTapTargets.comfortable,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? colors.accent : colors.tertiaryText,
      ),
      title: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.secondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}
