import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class CoolScreenBackground extends StatelessWidget {
  const CoolScreenBackground({
    required this.child,
    this.primaryColor = AppColors.accent,
    this.secondaryColor = AppColors.blue,
    super.key,
  });

  final Widget child;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.bg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -140,
            right: -96,
            child: _GlowOrb(
              size: 280,
              color: primaryColor.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            top: 120,
            left: -88,
            child: _GlowOrb(
              size: 220,
              color: secondaryColor.withValues(alpha: 0.1),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -72,
            child: _GlowOrb(
              size: 260,
              color: AppColors.purple.withValues(alpha: 0.08),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surface.withValues(alpha: 0.08),
                    Colors.transparent,
                    AppColors.bg.withValues(alpha: 0.92),
                  ],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: color.a * 0.25),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
