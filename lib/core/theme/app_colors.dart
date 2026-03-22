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
  static const darkBg = Color(0xFF080C09);
  static const darkSurface = Color(0xFF0D110E);
  static const darkSurface2 = Color(0xFF161D18);
  static const darkSurface3 = Color(0xFF1F2721);
  static const darkBorder = Color(0x1FFFFFFF);
  static const darkBorder2 = Color(0x2EFFFFFF);
  static const darkText = Color(0xFFF5F3EE);
  static const darkText2 = Color(0xFFB4BCB2);
  static const darkText3 = Color(0xFF7A857C);

  // Light semantic colors.
  static const lightBg = Color(0xFFF2F0EB);
  static const lightSurface = Color(0xFFFCFAF7);
  static const lightSurface2 = Color(0xFFF5F1EA);
  static const lightSurface3 = Color(0xFFE7E0D7);
  static const lightBorder = Color(0x1A0A0C0B);
  static const lightBorder2 = Color(0x260A0C0B);
  static const lightText = Color(0xFF0A0C0B);
  static const lightText2 = Color(0xFF4F584F);
  static const lightText3 = Color(0xFF7B837A);

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
  static const accent = Color(0xFF2C6A49);
  static const accent2 = Color(0xFF103322);
  static const accentGlow = Color(0x162C6A49);

  // Semantic colors.
  static const blue = Color(0xFF56728E);
  static const blueGlow = Color(0x1456728E);
  static const orange = Color(0xFFB57A30);
  static const purple = Color(0xFF7D6A8E);
  static const yellow = Color(0xFFD6AE65);
  static const red = Color(0xFFB85A65);

  // Brand partners.
  static const whatsapp = Color(0xFF2E8A57);

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
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
    transform: GradientRotation(135 * math.pi / 180),
  );

  static LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _useLightPalette
        ? const [Color(0xFFFEFCF8), Color(0xFFF5EFE6)]
        : const [Color(0xFF1C231E), Color(0xFF101511)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static LinearGradient get purpleGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _useLightPalette
        ? const [Color(0xFFF8F4FA), Color(0xFFEEE8F2)]
        : const [Color(0xFF16131A), Color(0xFF221D26)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static LinearGradient get blueGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _useLightPalette
        ? const [Color(0xFFF5F7FA), Color(0xFFE8EEF3)]
        : const [Color(0xFF141B1C), Color(0xFF1A2527)],
    transform: const GradientRotation(135 * math.pi / 180),
  );

  static const rsBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF031A43), rsBlue, rsBlueMid],
    transform: GradientRotation(135 * math.pi / 180),
  );

  static const rsHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF031A43), rsBlue, Color(0xFF0B2E66), rsGold],
    stops: [0, 0.45, 0.8, 1],
    transform: GradientRotation(135 * math.pi / 180),
  );
}
