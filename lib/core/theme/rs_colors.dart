import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rayon Sports FC ROUGEBLACK design-system colours.
///
/// Primary palette: Deep Navy, Rayon Red, Trophy Gold, Electric Mint.
/// This replaces the old Royal Blue system with the football-first
/// ROUGEBLACK visual identity.
abstract final class RsColors {
  // ── Core brand ──────────────────────────────────────────────────────
  /// Deep navy — primary background anchor.
  static const rsNavy = Color(0xFF0A0F2C);

  /// Midnight — elevated surfaces.
  static const rsNavyMid = Color(0xFF0D1333);

  /// Indigo wash — card surfaces.
  static const rsNavyLight = Color(0xFF131845);

  /// Soft navy — strong card surface.
  static const rsNavyPale = Color(0xFF1A2055);

  /// Rayon Red — primary accent, CTAs, active states.
  static const rsRed = Color(0xFFC8102E);

  /// Bright red — hover / strong accent.
  static const rsRedBright = Color(0xFFE01535);

  /// Dark red — deep accent anchor.
  static const rsRedDark = Color(0xFF8A0A1E);

  /// Trophy gold — rewards, membership, emphasis.
  static const rsGold = Color(0xFFD4A017);

  /// Soft gold — secondary gold for gradients.
  static const rsGoldLight = Color(0xFFF5D98B);

  /// Snow white — primary text.
  static const rsWhite = Color(0xFFF7F9FC);

  /// Steel gray — secondary text.
  static const rsSteel = Color(0xFF8892A4);

  /// Electric mint — success, positive states.
  static const rsMint = Color(0xFF00D4AA);

  /// Energy orange — warnings, urgency.
  static const rsOrange = Color(0xFFFF6B35);

  // ── Legacy aliases (keep old references compiling) ──────────────────
  static const rsBlue = rsNavy;
  static const rsBlueMid = rsNavyMid;
  static const rsBlueLight = rsNavyLight;
  static const rsBluePale = rsNavyPale;
  static const rsGoldSoft = rsGoldLight;
  static const rsBlueGlow = rsRedGlow;
  static const rsBlueBorder = rsRedBorder;

  // ── Glows & borders ─────────────────────────────────────────────────
  static const rsRedGlow = Color(0x59C8102E); // red at 35%
  static const rsRedBorder = Color(0x40C8102E); // red at 25%
  static const rsGoldGlow = Color(0x40D4A017); // gold at 25%

  // ── Glass tokens ────────────────────────────────────────────────────
  /// Standard glass surface opacity.
  static const double glassOpacity = 0.06;

  /// Strong glass surface opacity.
  static const double glassOpacityStrong = 0.12;

  /// Glass border opacity.
  static const double glassBorderOpacity = 0.15;

  // ── Gradient helpers ────────────────────────────────────────────────

  /// App background gradient (top → bottom).
  static const rsBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [rsNavyMid, rsNavy],
  );

  /// Dark card surface gradient at 135°.
  static const rsCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rsNavyLight, rsNavyMid],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Hero gradient: navy → red wash → transparent at 135°.
  static const rsHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D1333), Color(0xFF1A0A1A), Colors.transparent],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Membership card gradient at 135°.
  static const rsMembershipGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rsNavyLight, rsNavyPale, rsNavyMid],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Gold accent gradient.
  static const rsGoldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rsGold, rsGoldLight],
    transform: GradientRotation(135 * math.pi / 180),
  );

  /// Red CTA gradient (left → right).
  static const rsRedGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [rsRed, rsRedBright],
  );

  /// Support / initiative card gradient.
  static const rsSupportGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rsNavyLight, rsNavyPale],
    transform: GradientRotation(135 * math.pi / 180),
  );
}
