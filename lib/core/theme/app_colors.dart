import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Legacy dark-first design-system color palette for the Cool app.
///
/// Theme-aware semantic tokens now live in [CoolPalette]. The semantic getters
/// in this class mirror the active app brightness so older screens still adapt
/// while they migrate onto direct palette reads.
abstract final class AppColors {
  static bool _useLightPalette = false;

  static void applyBrightness(Brightness brightness) {
    _useLightPalette = brightness == Brightness.light;
  }

  // Dark semantic colors.
  static const darkBg = Color(0xFF0A0A0F);
  static const darkSurface = Color(0xFF13131A);
  static const darkSurface2 = Color(0xFF1C1C26);
  static const darkSurface3 = Color(0xFF252532);
  static const darkBorder = Color(0x12FFFFFF);
  static const darkBorder2 = Color(0x1FFFFFFF);
  static const darkText = Color(0xFFF0F0F5);
  static const darkText2 = Color(0xFF8888A0);
  static const darkText3 = Color(0xFF555568);

  // Light semantic colors.
  static const lightBg = Color(0xFFF7F8FC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFF0F2F7);
  static const lightSurface3 = Color(0xFFE4E7EF);
  static const lightBorder = Color(0x140A0A0F);
  static const lightBorder2 = Color(0x220A0A0F);
  static const lightText = Color(0xFF10131C);
  static const lightText2 = Color(0xFF5C6679);
  static const lightText3 = Color(0xFF8B93A4);

  // Backgrounds and surfaces.
  static Color get bg => _useLightPalette ? lightBg : darkBg;
  static Color get surface => _useLightPalette ? lightSurface : darkSurface;
  static Color get surface2 => _useLightPalette ? lightSurface2 : darkSurface2;
  static Color get surface3 => _useLightPalette ? lightSurface3 : darkSurface3;

  // Borders.
  static Color get border => _useLightPalette ? lightBorder : darkBorder;
  static Color get border2 => _useLightPalette ? lightBorder2 : darkBorder2;

  // Text.
  static Color get text => _useLightPalette ? lightText : darkText;
  static Color get text2 => _useLightPalette ? lightText2 : darkText2;
  static Color get text3 => _useLightPalette ? lightText3 : darkText3;

  // Accent and brand colors.
  static const accent = Color(0xFF00E5A0);
  static const accent2 = Color(0xFF00B87A);
  static const accentGlow = Color(0x1400E5A0);

  // Semantic colors.
  static const blue = Color(0xFF4D8EFF);
  static const blueGlow = Color(0x144D8EFF);
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
  static const rsBlueGlow = Color(0x200047AB);
  static const rsBlueBorder = Color(0x590055CC);

  // Gradient helpers.
  static final accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [accent, blue],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _useLightPalette
        ? const [Color(0xFFFFFFFF), Color(0xFFF0F3FA)]
        : const [Color(0xFF151520), Color(0xFF1A1A28)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static LinearGradient get purpleGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _useLightPalette
        ? const [Color(0xFFF7F0FF), Color(0xFFEADFFF)]
        : const [Color(0xFF12102A), Color(0xFF1A1040)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static LinearGradient get blueGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _useLightPalette
        ? const [Color(0xFFF2F7FF), Color(0xFFE2ECFF)]
        : const [Color(0xFF0D1B2A), Color(0xFF1A2D4A)],
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
