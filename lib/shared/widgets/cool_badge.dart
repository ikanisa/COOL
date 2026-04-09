import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Badge variants — Tactile Monolith system.
enum CoolBadgeVariant {
  primary,
  secondary,
  outline,
  success,
  warning,
  danger,
  accent,
}

/// Badge sizes.
enum CoolBadgeSize {
  sm,
  md;

  EdgeInsets get padding => switch (this) {
    CoolBadgeSize.sm => const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    CoolBadgeSize.md => const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  };

  double get fontSize => switch (this) {
    CoolBadgeSize.sm => 9,
    CoolBadgeSize.md => 10,
  };
}

/// A pill-shaped badge — Tactile Monolith system.
///
/// JetBrains Mono, bold, uppercase, widest tracking.
class CoolBadge extends StatelessWidget {
  const CoolBadge({
    required this.label,
    this.variant = CoolBadgeVariant.primary,
    this.size = CoolBadgeSize.sm,
    this.icon,
    super.key,
  });

  final String label;
  final CoolBadgeVariant variant;
  final CoolBadgeSize size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final bg = _resolvedBg(colors);
    final fg = _resolvedFg(colors);
    final border = _resolvedBorder(colors);

    return Container(
      padding: size.padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: border != null ? Border.all(color: border, width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size.fontSize + 2, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: context.coolText
                .mobiLabel(color: fg)
                .copyWith(
                  fontSize: size.fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                ),
          ),
        ],
      ),
    );
  }

  Color _resolvedBg(CoolSemanticColors colors) => switch (variant) {
    CoolBadgeVariant.primary => colors.accent.withValues(alpha: 0.15),
    CoolBadgeVariant.secondary => colors.chipBackground,
    CoolBadgeVariant.outline => Colors.transparent,
    CoolBadgeVariant.success => colors.success.withValues(alpha: 0.15),
    CoolBadgeVariant.warning => colors.warning.withValues(alpha: 0.15),
    CoolBadgeVariant.danger => colors.danger.withValues(alpha: 0.15),
    CoolBadgeVariant.accent => colors.accentGold.withValues(alpha: 0.15),
  };

  Color _resolvedFg(CoolSemanticColors colors) => switch (variant) {
    CoolBadgeVariant.primary => colors.accent,
    CoolBadgeVariant.secondary => colors.secondaryText,
    CoolBadgeVariant.outline => colors.primaryText,
    CoolBadgeVariant.success => colors.success,
    CoolBadgeVariant.warning => colors.warning,
    CoolBadgeVariant.danger => colors.danger,
    CoolBadgeVariant.accent => colors.accentGold,
  };

  Color? _resolvedBorder(CoolSemanticColors colors) => switch (variant) {
    CoolBadgeVariant.outline => Colors.white.withValues(alpha: 0.10),
    _ => null,
  };
}
