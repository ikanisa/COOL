part of 'home_sections.dart';

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final imageUrl = avatarUrl?.trim() ?? '';

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.cardSurface,
        boxShadow: CoolShadows.ambientFloat(strength: 0.4),
      ),
      child: ClipOval(
        child: imageUrl.isEmpty
            ? const _AvatarFallback()
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) => const _AvatarFallback(),
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CoolBrandMark(size: 28));
  }
}

class _HomeIconButton extends StatelessWidget {
  const _HomeIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(CoolRadii.md),
        onTap: onTap,
        child: Ink(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: colors.appBackground,
            borderRadius: BorderRadius.circular(CoolRadii.md),
          ),
          child: Icon(icon, size: 24, color: colors.primaryText),
        ),
      ),
    );
  }
}

class _MonthlyMovementPill extends StatelessWidget {
  const _MonthlyMovementPill({required this.monthlyNetChange});

  final int? monthlyNetChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final amount = monthlyNetChange ?? 0;
    final isPositive = amount >= 0;
    final accent = amount == 0
        ? colors.secondaryText
        : isPositive
        ? colors.success
        : colors.danger;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x4,
        vertical: CoolSpace.x3,
      ),
      decoration: BoxDecoration(
        color: colors.shadowColor.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(CoolRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            amount == 0
                ? Icons.horizontal_rule_rounded
                : isPositive
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: CoolSpace.x2),
          Flexible(
            child: Text(
              summarizeMonthlyMovement(context, amount),
              style: context.coolText.mono(
                Theme.of(context).textTheme.labelSmall,
                color: accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.85,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
