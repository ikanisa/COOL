part of '../screens/create_group_screen.dart';

// ─── Section label (monospace, uppercase) ─────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Text(
      label,
      style: text.mono(
        theme.textTheme.labelSmall,
        fontWeight: FontWeight.w700,
        color: colors.secondaryText,
        letterSpacing: 1.0,
      ),
    );
  }
}

// ─── Type card (saving vs community) ──────────────────────────────────────

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title group type',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CoolRadii.md),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(
              vertical: CoolSpace.x5,
              horizontal: CoolSpace.x4,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.chipSelectedBackground
                  : colors.cardSurface,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(
                color: isSelected ? colors.accent : colors.border,
                width: isSelected ? 1.6 : 1.1,
              ),
            ),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(height: CoolSpace.x2),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: text.rayon(
                    theme.textTheme.labelLarge,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? colors.accent : colors.primaryText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: text.mono(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                    letterSpacing: 0.5,
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

// ─── Two-card row ─────────────────────────────────────────────────────────

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

// ─── Selection chip (pill, uppercase) ─────────────────────────────────────

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({
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
    final text = context.coolText;
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label option',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          onTap: onTap,
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(
              horizontal: CoolSpace.x4,
              vertical: CoolSpace.x3,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.chipSelectedBackground
                  : colors.cardSurface,
              borderRadius: BorderRadius.circular(CoolRadii.pill),
              border: Border.all(
                color: isSelected ? colors.accent : colors.border,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: text.mono(
                theme.textTheme.labelMedium,
                fontWeight: FontWeight.w700,
                color: isSelected ? colors.accent : colors.secondaryText,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Info banner ──────────────────────────────────────────────────────────

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
    final text_ = context.coolText;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4 - 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
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
              style: text_.rayon(
                theme.textTheme.bodyMedium,
                fontWeight: FontWeight.w600,
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
