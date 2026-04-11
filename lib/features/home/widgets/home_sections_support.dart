part of 'home_sections.dart';

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final imageUrl = avatarUrl?.trim() ?? '';

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.cardSurface,
        border: Border.all(color: colors.border),
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(CoolRadii.md),
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, size: 20, color: colors.primaryText),
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
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x2,
      ),
      decoration: BoxDecoration(
        color: colors.accentForeground.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(CoolRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            amount == 0
                ? CoolIcons.horizontalRule
                : isPositive
                ? CoolIcons.trendUp
                : CoolIcons.trendDown,
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
