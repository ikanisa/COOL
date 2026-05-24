import 'package:flutter/material.dart';

class CollectShadows {
  const CollectShadows._();

  static List<BoxShadow> card(bool isDark) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> soft(bool isDark) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
        blurRadius: 14,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
