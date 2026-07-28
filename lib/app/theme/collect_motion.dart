import 'package:flutter/material.dart';

class CollectMotion {
  const CollectMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;

  static bool isReduced(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations == true;
  }

  static Duration duration(BuildContext context, Duration value) {
    return isReduced(context) ? Duration.zero : value;
  }

  static AnimationStyle? animationStyle(BuildContext context) {
    return isReduced(context) ? AnimationStyle.noAnimation : null;
  }
}
