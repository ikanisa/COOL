import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A reusable dark-surface card used throughout the Cool app.
///
/// Defaults to [AppColors.surface2] background with a 1 px border and
/// 20 px corner radius. Supports an optional [gradient] overlay and
/// custom tap handling with an accent-glow splash.
class CoolCard extends StatelessWidget {
  const CoolCard({
    required this.child,
    this.padding,
    this.onTap,
    this.borderColor,
    this.borderRadius,
    this.gradient,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double? borderRadius;
  final Gradient? gradient;

  static const _defaultRadius = 20.0;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? _defaultRadius;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? AppColors.border),
    );
    final decoration = ShapeDecoration(
      shape: shape,
      gradient: gradient ?? AppColors.cardGradient,
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 28,
          offset: const Offset(0, 16),
        ),
        BoxShadow(
          color: (borderColor ?? AppColors.border2).withValues(alpha: 0.16),
          blurRadius: 0,
          offset: const Offset(0, 0),
        ),
      ],
    );

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: decoration,
          child: InkWell(
            onTap: onTap,
            splashColor: AppColors.accentGlow,
            highlightColor: Colors.transparent,
            child: content,
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(decoration: decoration, child: content),
    );
  }
}
