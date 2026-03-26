import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand/app_brand.dart';
import '../../core/theme/cool_foundations.dart';

class CoolScreenBackground extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final brand = ref.watch(appBrandProvider);

    if (!showGlow) {
      return DecoratedBox(
        decoration: BoxDecoration(color: colors.appBackground),
        child: child,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectivePrimary =
        primaryColor ??
        (brand.isRayonDominant ? brand.primaryColor : colors.accent);
    final effectiveSecondary =
        secondaryColor ??
        (brand.isRayonDominant ? brand.secondaryColor : colors.info);

    final accentGlow = effectivePrimary.withValues(alpha: isDark ? 0.14 : 0.08);
    final secondaryGlow = effectiveSecondary.withValues(
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
                colors.appBackground.withValues(alpha: isDark ? 0.18 : 0.04),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
