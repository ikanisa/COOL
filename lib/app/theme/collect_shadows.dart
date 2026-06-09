import 'package:flutter/material.dart';

import 'collect_colors.dart';

class CollectShadows {
  const CollectShadows._();

  static List<BoxShadow> card() {
    return [
      BoxShadow(
        color: CollectColors.brandPeriwinkle.withValues(alpha: 0.07),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> soft() {
    return [
      BoxShadow(
        color: CollectColors.brandPeriwinkle.withValues(alpha: 0.05),
        blurRadius: 14,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
