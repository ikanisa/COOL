import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Shared low-noise header surface for app bars and pinned top chrome.
class CoolGlassHeaderSurface extends StatelessWidget {
  const CoolGlassHeaderSurface({
    this.blur = CoolBlur.subtle,
    this.opacity = 0.96,
    this.showBottomGhostEdge = true,
    super.key,
  });

  final double blur;
  final double opacity;
  final bool showBottomGhostEdge;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final mediaQuery = MediaQuery.of(context);
    final reduceBlur = mediaQuery.disableAnimations ||
        mediaQuery.accessibleNavigation;
    final effectiveBlur = reduceBlur ? 0.0 : blur;

    final decoration = BoxDecoration(
      color: colors.elevatedBackground.withValues(alpha: opacity),
      border: showBottomGhostEdge
          ? Border(bottom: BorderSide(color: colors.border, width: 0.8))
          : null,
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: colors.shadowColor.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );

    if (effectiveBlur <= 0) {
      return DecoratedBox(decoration: decoration);
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: DecoratedBox(decoration: decoration),
      ),
    );
  }
}
