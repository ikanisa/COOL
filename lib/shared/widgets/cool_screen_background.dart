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

  /// Retained for backward compatibility; no longer produces visible glow.
  final Color primaryColor;

  /// Retained for backward compatibility; produces a very subtle top veil.
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.bg),
      child: child,
    );
  }
}
