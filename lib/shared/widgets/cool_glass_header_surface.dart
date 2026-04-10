import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Shared frosted-glass header surface for app bars and pinned top chrome.
class CoolGlassHeaderSurface extends StatelessWidget {
  const CoolGlassHeaderSurface({
    this.blur = CoolBlur.overlay,
    this.opacity = 0.84,
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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                colors.glassSurface.withValues(alpha: opacity),
                colors.appBackground.withValues(alpha: opacity * 0.92),
              ],
            ),
            border: showBottomGhostEdge
                ? Border(
                    bottom: BorderSide(
                      color: colors.borderStrong.withValues(alpha: 0.15),
                      width: 0.75,
                    ),
                  )
                : null,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: colors.highlightColor.withValues(alpha: 0.45),
                blurRadius: 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
