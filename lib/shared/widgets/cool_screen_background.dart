import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand/app_brand.dart';
import '../../core/theme/cool_foundations.dart';
import 'atmospheric_background.dart';

/// Universal screen background for the Mobi × Rayon design system.
///
/// Renders the atmospheric blurred-blob layer + mobi-grid (24px crosshatch
/// at white/8%) behind all content, then applies brand-aware radial glows.
///
/// Every screen in the app uses this widget, either directly or via one of the
/// scaffold wrappers ([CoreTabRootScaffold], [CoreDetailScaffold], etc.).
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

    final effectivePrimary =
        primaryColor ??
        (brand.isRayonDominant ? brand.primaryColor : colors.accent);
    final effectiveSecondary =
        secondaryColor ??
        (brand.isRayonDominant ? brand.secondaryColor : colors.info);

    final accentGlow = effectivePrimary.withValues(alpha: 0.14);
    final secondaryGlow = effectiveSecondary.withValues(alpha: 0.10);
    const topWash = Colors.transparent;
    final bottomShade = colors.shadowColor.withValues(alpha: 0.16);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Base gradient ────────────────────────────────────────
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

        // ── Atmospheric blobs + mobi-grid (same as home screen) ─
        const AtmosphericBackground(showGrid: true),

        // ── Brand accent glow (top-left) ────────────────────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.95, -1.1),
              radius: 1.0,
              colors: <Color>[accentGlow, Colors.transparent],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        // ── Secondary glow (top-right) ──────────────────────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1.05, -0.8),
              radius: 1.15,
              colors: <Color>[secondaryGlow, Colors.transparent],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        // ── Center wash ─────────────────────────────────────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, -0.2),
              radius: 1.4,
              colors: <Color>[
                effectivePrimary.withValues(alpha: 0.10),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),

        // ── Bottom fade ─────────────────────────────────────────
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.transparent,
                colors.appBackground.withValues(alpha: 0.18),
              ],
            ),
          ),
        ),
        // ── Bottom shadow vignette ──────────────────────────────
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, 0.95),
                radius: 1.1,
                colors: <Color>[
                  colors.shadowColor.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),

        // ── Content ─────────────────────────────────────────────
        child,
      ],
    );
  }
}
