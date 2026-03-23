import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A restrained premium glass surface.
class CoolGlassCard extends StatelessWidget {
  const CoolGlassCard({
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius = CoolRadii.xl,
    this.blur = CoolBlur.overlay,
    this.opacity = 0.82,
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
    final colors = context.coolSemanticColors;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final glassColor = colors.glassSurface.withValues(
      alpha: isDark ? opacity - 0.06 : opacity,
    );
    final borderCol =
        borderColor ?? colors.border.withValues(alpha: isDark ? 0.55 : 0.35);

    final content = Padding(
      padding: padding ?? CoolSpace.sectionPadding,
      child: child,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glassColor,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colors.highlightColor.withValues(alpha: isDark ? 0.08 : 0.18),
                colors.buttonPrimaryBackground.withValues(
                  alpha: isDark ? 0.03 : 0.02,
                ),
                Colors.transparent,
              ],
              stops: const <double>[0.0, 0.28, 1.0],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: hasBorder
                ? Border.all(color: borderCol!, width: 1.0)
                : null,
            boxShadow: CoolShadows.glass(brightness),
          ),
          child: Material(
            color: Colors.transparent,
            child: onTap == null
                ? content
                : InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(borderRadius),
                    splashColor: colors.buttonPrimaryBackground.withValues(
                      alpha: 0.05,
                    ),
                    highlightColor: Colors.transparent,
                    child: content,
                  ),
          ),
        ),
      ),
    );
  }
}
