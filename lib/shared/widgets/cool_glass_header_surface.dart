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

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
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
          ),
        ),
      ),
    );
  }
}
