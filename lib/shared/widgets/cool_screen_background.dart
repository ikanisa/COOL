import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/cool_foundations.dart';

/// Universal screen background for the minimalist app surfaces.
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
    final base = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[colors.elevatedBackground, colors.appBackground],
        ),
      ),
      child: child,
    );

    if (!showGlow) {
      return base;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        ExcludeSemantics(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.25, -0.95),
                  radius: 0.9,
                  colors: <Color>[
                    (primaryColor ?? colors.accentStrong).withValues(
                      alpha: 0.06,
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        ExcludeSemantics(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.2, -0.8),
                  radius: 0.75,
                  colors: <Color>[
                    (secondaryColor ?? colors.accent).withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
