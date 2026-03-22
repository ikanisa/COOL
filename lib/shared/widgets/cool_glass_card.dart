import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_palette.dart';

/// A restrained premium glass surface.
class CoolGlassCard extends StatelessWidget {
  const CoolGlassCard({
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius = CoolRadii.xl,
    this.blur = CoolBlur.standard,
    this.opacity = 0.84,
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
    final colors = context.coolSemanticColors;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    final glassColor = colors.glassSurface.withValues(
      alpha: isDark ? opacity - 0.06 : opacity,
    );
    final borderCol =
        borderColor ?? colors.border.withValues(alpha: isDark ? 0.95 : 0.7);

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
                colors.highlightColor.withValues(alpha: isDark ? 0.04 : 0.30),
                colors.accent.withValues(alpha: isDark ? 0.04 : 0.03),
                Colors.transparent,
              ],
              stops: const <double>[0.0, 0.28, 1.0],
            ),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderCol, width: 1.0),
            boxShadow: CoolShadows.glass(brightness),
          ),
          child: Material(
            color: Colors.transparent,
            child: onTap == null
                ? content
                : InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(borderRadius),
                    splashColor: palette.accent.withValues(alpha: 0.06),
                    highlightColor: Colors.transparent,
                    child: content,
                  ),
          ),
        ),
      ),
    );
  }
}
