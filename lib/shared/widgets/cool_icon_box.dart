import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Standardized icon container sizes.
enum CoolIconBoxSize {
  sm,
  md,
  lg;

  double get dimension => switch (this) {
    CoolIconBoxSize.sm => 36,
    CoolIconBoxSize.md => 44,
    CoolIconBoxSize.lg => 56,
  };

  double get iconSize => switch (this) {
    CoolIconBoxSize.sm => 18,
    CoolIconBoxSize.md => 22,
    CoolIconBoxSize.lg => 28,
  };

  double get radius => switch (this) {
    CoolIconBoxSize.sm => CoolRadii.xs,
    CoolIconBoxSize.md => CoolRadii.md,
    CoolIconBoxSize.lg => CoolRadii.md,
  };
}

enum CoolIconBoxVariant { tinted, solid, glass }

/// A standardized icon container used in cards, rows, and empty states.
class CoolIconBox extends StatelessWidget {
  const CoolIconBox({
    required this.icon,
    this.accent,
    this.size = CoolIconBoxSize.md,
    this.variant = CoolIconBoxVariant.tinted,
    this.iconWidget,
    super.key,
  });

  const CoolIconBox.solid({
    required this.icon,
    this.accent,
    this.size = CoolIconBoxSize.md,
    this.iconWidget,
    super.key,
  }) : variant = CoolIconBoxVariant.solid;

  const CoolIconBox.glass({
    required this.icon,
    this.accent,
    this.size = CoolIconBoxSize.md,
    this.iconWidget,
    super.key,
  }) : variant = CoolIconBoxVariant.glass;

  final IconData icon;
  final Color? accent;
  final CoolIconBoxSize size;
  final CoolIconBoxVariant variant;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final resolvedAccent = accent ?? colors.accent;
    final dim = size.dimension;
    final rad = size.radius;

    final bg = switch (variant) {
      CoolIconBoxVariant.tinted => resolvedAccent.withValues(alpha: 0.12),
      CoolIconBoxVariant.solid => colors.cardSurfaceStrong,
      CoolIconBoxVariant.glass => colors.glassSurface,
    };

    final child =
        iconWidget ?? Icon(icon, color: resolvedAccent, size: size.iconSize);

    return Container(
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(rad),
        border: Border.all(color: colors.border),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
