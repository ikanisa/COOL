import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/cool_palette.dart';

class CoolScreenBackground extends StatelessWidget {
  const CoolScreenBackground({
    required this.child,
    this.primaryColor,
    this.secondaryColor,
    this.showGlow = true,
    super.key,
  });

  final Widget child;

  final Color? primaryColor;

  final Color? secondaryColor;

  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final colors = context.coolSemanticColors;

    if (!showGlow) {
      return DecoratedBox(
        decoration: BoxDecoration(color: colors.appBackground),
        child: child,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentGlow = (primaryColor ?? colors.accent).withValues(
      alpha: isDark ? 0.14 : 0.08,
    );
    final secondaryGlow = (secondaryColor ?? colors.info).withValues(
      alpha: isDark ? 0.10 : 0.05,
    );
    final topWash = colors.highlightColor.withValues(
      alpha: isDark ? 0.0 : 0.32,
    );
    final bottomShade = colors.shadowColor.withValues(
      alpha: isDark ? 0.16 : 0.02,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                topWash,
                colors.shellGradientTop,
                colors.shellGradientBottom,
                bottomShade,
              ],
              stops: const [0.0, 0.18, 0.88, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.85, -0.95),
              radius: 1.05,
              colors: <Color>[accentGlow, Colors.transparent],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.15, -0.9),
              radius: 1.25,
              colors: <Color>[secondaryGlow, Colors.transparent],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.transparent,
                palette.bg.withValues(alpha: isDark ? 0.18 : 0.04),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
