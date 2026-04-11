import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/cool_foundations.dart';

/// Universal screen background for the Tactile Monolith design system.
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
    
    if (!showGlow) {
      return DecoratedBox(
        decoration: BoxDecoration(color: colors.appBackground),
        child: child,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Base color ──────────────────────────────────────────
        DecoratedBox(
          decoration: BoxDecoration(color: colors.appBackground),
        ),
        
        // ── Top linear shadow fade ──────────────────────────────
        ExcludeSemantics(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    colors.shadowColor,
                    colors.appBackground,
                    colors.appBackground,
                  ],
                  stops: const <double>[0.0, 0.32, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ── Primary glow (top-left) ─────────────────────────────
        ExcludeSemantics(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.15, -0.9),
                  radius: 0.95,
                  colors: <Color>[
                    (primaryColor ?? colors.accentStrong).withValues(alpha: 0.26),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Secondary glow (top-right) ──────────────────────────
        ExcludeSemantics(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.15, -0.4),
                  radius: 0.9,
                  colors: <Color>[
                    (secondaryColor ?? colors.accent).withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
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
