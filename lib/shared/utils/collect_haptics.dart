import 'package:flutter/services.dart';

class CollectHaptics {
  const CollectHaptics._();

  static void selection() {
    HapticFeedback.selectionClick();
  }

  static void lightImpact() {
    HapticFeedback.lightImpact();
  }

  static void mediumImpact() {
    HapticFeedback.mediumImpact();
  }

  static void warning() {
    HapticFeedback.vibrate();
  }
}
