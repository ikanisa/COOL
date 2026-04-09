part of 'home_sections.dart';

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.avatarUrl, required this.initials});

  final String? avatarUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final imageUrl = avatarUrl?.trim() ?? '';

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: HomeVisualPalette.outlineStrong),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: imageUrl.isEmpty
            ? _AvatarFallback(initials: initials)
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) =>
                    _AvatarFallback(initials: initials),
              ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF20242B), Color(0xFF0E1014)],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: context.coolText.mono(
            Theme.of(context).textTheme.labelMedium,
            color: HomeVisualPalette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _HomeIconButton extends StatelessWidget {
  const _HomeIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(CoolRadii.md),
        onTap: onTap,
        child: Ink(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: HomeVisualPalette.surfaceMuted,
            borderRadius: BorderRadius.circular(CoolRadii.md),
            border: Border.all(color: HomeVisualPalette.outline),
          ),
          child: Icon(icon, size: 24, color: HomeVisualPalette.textPrimary),
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
    final amount = monthlyNetChange ?? 0;
    final isPositive = amount >= 0;
    final accent = amount == 0
        ? Colors.white.withValues(alpha: 0.74)
        : isPositive
        ? const Color(0xFFD7FFEA)
        : const Color(0xFFFFDFE3);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x4,
        vertical: CoolSpace.x3,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
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
              summarizeMonthlyMovement(amount),
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
