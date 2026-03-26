import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_press_feedback.dart';

/// A restrained premium glass surface.
///
/// Uses [CoolGlassOpacity] tokens for per-mode alpha values and
/// [CoolPressFeedback] for tactile press animation when tappable.
class CoolGlassCard extends StatelessWidget {
  const CoolGlassCard({
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius = CoolRadii.xl,
    this.blur = CoolBlur.heavy,
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

    // Use CoolGlassOpacity tokens for mode-aware alpha values.
    final bgAlpha = CoolGlassOpacity.glassBackground(brightness);
    final borderAlpha = CoolGlassOpacity.glassBorderWhite(brightness);
    final gradientAlpha = CoolGlassOpacity.glassGradientWhite(brightness);

    final glassColor = colors.glassSurface.withValues(alpha: bgAlpha * opacity);
    final borderCol =
        borderColor ?? colors.highlightColor.withValues(alpha: borderAlpha);

    final content = Padding(
      padding: padding ?? CoolSpace.sectionPadding,
      child: child,
    );

    final glass = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glassColor,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                colors.highlightColor.withValues(alpha: gradientAlpha),
                colors.accent.withValues(alpha: isDark ? 0.06 : 0.03),
                colors.shadowColor.withValues(alpha: isDark ? 0.12 : 0.03),
              ],
              stops: const <double>[0.0, 0.38, 1.0],
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

    // Wrap tappable glass cards with press feedback.
    if (onTap != null) {
      return CoolPressFeedback(onTap: onTap!, child: glass);
    }
    return glass;
  }
}
