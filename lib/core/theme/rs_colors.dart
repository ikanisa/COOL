import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rayon Sports FC design-system colours.
///
/// Extends the Cool palette with the club's Deep Blue, White, and Gold.
abstract final class RsColors {
  // ── Core brand ──────────────────────────────────────────────────────
  static const rsBlue = Color(0xFF0047AB);
  static const rsBlueMid = Color(0xFF0055CC);
  static const rsBlueLight = Color(0xFF1A6FE8);
  static const rsBluePale = Color(0xFF3D8BFF);
  static const rsWhite = Color(0xFFF4F6FA);
  static const rsGold = Color(0xFFC9A84C);
  static const rsGoldLight = Color(0xFFE8C96A);

  // ── Glows & borders ─────────────────────────────────────────────────
  static const rsBlueGlow = Color(0x400047AB);
  static const rsBlueBorder = Color(0x590055CC);

  // ── Gradient helpers ────────────────────────────────────────────────

  /// Dark card surface gradient at 135°.
  static const rsCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF091540), Color(0xFF0D1E6A)],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Hero gradient: 3-stop blue → transparent at 135°.
  static const rsHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF001A5C), Color(0xFF00115A), Colors.transparent],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Membership card gradient at 135°.
  static const rsMembershipGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A1F60), Color(0xFF0D2878), Color(0xFF0047AB)],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Gold accent gradient.
  static const rsGoldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rsGold, rsGoldLight],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Support / initiative card gradient.
  static const rsSupportGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E1A4A), Color(0xFF152260)],
    transform: GradientRotation(135 * math.pi / 180),
  );
}
