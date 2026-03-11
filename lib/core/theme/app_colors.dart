import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Design-system color palette for the Cool app.
abstract final class AppColors {
  // Backgrounds and surfaces.
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF13131A);
  static const surface2 = Color(0xFF1C1C26);
  static const surface3 = Color(0xFF252532);

  // Borders.
  static const border = Color(0x12FFFFFF);
  static const border2 = Color(0x1FFFFFFF);

  // Text.
  static const text = Color(0xFFF0F0F5);
  static const text2 = Color(0xFF8888A0);
  static const text3 = Color(0xFF555568);

  // Accent and brand colors.
  static const accent = Color(0xFF00E5A0);
  static const accent2 = Color(0xFF00B87A);
  static const accentGlow = Color(0x2600E5A0);

  // Semantic colors.
  static const blue = Color(0xFF4D8EFF);
  static const blueGlow = Color(0x264D8EFF);
  static const orange = Color(0xFFFF6B35);
  static const purple = Color(0xFF9B6DFF);
  static const yellow = Color(0xFFFFD166);
  static const red = Color(0xFFFF4D6A);

  // Brand partners.
  static const whatsapp = Color(0xFF25D166);

  // Rayon Sports FC.
  static const rsBlue = Color(0xFF0047AB);
  static const rsBlueMid = Color(0xFF0055CC);
  static const rsBlueLight = Color(0xFF1A6FE8);
  static const rsBluePale = Color(0xFF3D8BFF);
  static const rsWhite = Color(0xFFF4F6FA);
  static const rsGold = Color(0xFFC9A84C);
  static const rsGoldLight = Color(0xFFE8C96A);
  static const rsBlueGlow = Color(0x400047AB);
  static const rsBlueBorder = Color(0x590055CC);

  // Gradient helpers.
  static final accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [accent, blue],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static final cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [Color(0xFF161622), Color(0xFF1E1E30)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static final purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [Color(0xFF12102A), Color(0xFF1A1040)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static final blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [Color(0xFF0D1B2A), Color(0xFF1A2D4A)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static final rsBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [Color(0xFF031A43), rsBlue, rsBlueMid],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static final rsHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [Color(0xFF031A43), rsBlue, Color(0xFF0B2E66), rsGold],
    stops: const [0, 0.45, 0.8, 1],
    transform: const GradientRotation(135 * math.pi / 180),
  );
}
