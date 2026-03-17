import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/cool_palette.dart';

/// A high-end glassmorphic card with blur and thin borders.
/// Follows the "Soft Liquid Glass" aesthetic.
class CoolGlassCard extends StatelessWidget {
  const CoolGlassCard({
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius = 28.0,
    this.blur = 10.0,
    this.opacity = 0.05,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final double borderRadius;
  final double blur;
  final double opacity;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark ? Colors.white : Colors.black;
    final glassColor = baseColor.withValues(alpha: opacity);
    final borderCol = borderColor ?? palette.border.withValues(alpha: 0.2);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glassColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderCol, width: 1.0),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(borderRadius),
              splashColor: palette.accent.withValues(alpha: 0.05),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: padding ?? const EdgeInsets.all(18),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
