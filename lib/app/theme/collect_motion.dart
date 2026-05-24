import 'package:flutter/material.dart';

class CollectMotion {
  const CollectMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;

  static Duration duration(BuildContext context, Duration value) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : value;
  }
}
