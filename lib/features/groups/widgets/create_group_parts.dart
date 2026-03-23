part of '../screens/create_group_screen.dart';

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title group type',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.all(Radius.circular(radii.md)),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(
              vertical: CoolSpace.x5 - 2,
              horizontal: CoolSpace.x4 - 2,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.chipSelectedBackground
                  : colors.cardSurface,
              borderRadius: BorderRadius.all(Radius.circular(radii.md)),
              border: Border.all(
                color: isSelected ? colors.accent : colors.border,
                width: isSelected ? 1.6 : 1.1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: isSelected ? colors.accent : colors.primaryText,
                ),
                const SizedBox(height: CoolSpace.x2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isSelected ? colors.accent : colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1 / 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptiveCardPair extends StatelessWidget {
  const _AdaptiveCardPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: CoolSpace.x3),
        Expanded(child: second),
      ],
    );
  }
}

class _BankChip extends StatelessWidget {
  const _BankChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radii = context.coolRadii;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label option',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.all(Radius.circular(radii.pill)),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: CoolSpace.x3,
              vertical: CoolSpace.x3,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.chipSelectedBackground
                  : colors.cardSurface,
              borderRadius: BorderRadius.all(Radius.circular(radii.pill)),
              border: Border.all(
                color: isSelected ? colors.accent : colors.border,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected ? colors.accent : colors.secondaryText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4 - 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: CoolSpace.x3 - 2),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
