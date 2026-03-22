import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-aware semantic color roles for the Cool app shell.
///
/// New and migrated widgets should read semantic colors from the active theme
/// instead of using the legacy dark-first [AppColors] surface/text tokens.
@immutable
class CoolPalette extends ThemeExtension<CoolPalette> {
  const CoolPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.border2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accent2,
    required this.accentGlow,
    required this.blue,
    required this.blueGlow,
    required this.orange,
    required this.purple,
    required this.yellow,
    required this.red,
  });

  static const dark = CoolPalette(
    bg: AppColors.darkBg,
    surface: AppColors.darkSurface,
    surface2: AppColors.darkSurface2,
    surface3: AppColors.darkSurface3,
    border: AppColors.darkBorder,
    border2: AppColors.darkBorder2,
    text: AppColors.darkText,
    text2: AppColors.darkText2,
    text3: AppColors.darkText3,
    accent: AppColors.accent,
    accent2: AppColors.accent2,
    accentGlow: Color(0x262C6A49),
    blue: AppColors.blue,
    blueGlow: Color(0x2456728E),
    orange: AppColors.orange,
    purple: AppColors.purple,
    yellow: AppColors.yellow,
    red: AppColors.red,
  );

  static const light = CoolPalette(
    bg: AppColors.lightBg,
    surface: AppColors.lightSurface,
    surface2: AppColors.lightSurface2,
    surface3: AppColors.lightSurface3,
    border: AppColors.lightBorder,
    border2: AppColors.lightBorder2,
    text: AppColors.lightText,
    text2: AppColors.lightText2,
    text3: AppColors.lightText3,
    accent: AppColors.accent,
    accent2: AppColors.accent2,
    accentGlow: AppColors.accentGlow,
    blue: AppColors.blue,
    blueGlow: AppColors.blueGlow,
    orange: AppColors.orange,
    purple: AppColors.purple,
    yellow: AppColors.yellow,
    red: AppColors.red,
  );

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color border2;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accent2;
  final Color accentGlow;
  final Color blue;
  final Color blueGlow;
  final Color orange;
  final Color purple;
  final Color yellow;
  final Color red;

  Color get borderStrong => border2;
  Color get textMuted => text2;
  Color get textSubtle => text3;
  Color get accentSoft => accentGlow;

  @override
  CoolPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? border2,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accent2,
    Color? accentGlow,
    Color? blue,
    Color? blueGlow,
    Color? orange,
    Color? purple,
    Color? yellow,
    Color? red,
  }) {
    return CoolPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      border: border ?? this.border,
      border2: border2 ?? this.border2,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accent2: accent2 ?? this.accent2,
      accentGlow: accentGlow ?? this.accentGlow,
      blue: blue ?? this.blue,
      blueGlow: blueGlow ?? this.blueGlow,
      orange: orange ?? this.orange,
      purple: purple ?? this.purple,
      yellow: yellow ?? this.yellow,
      red: red ?? this.red,
    );
  }

  @override
  CoolPalette lerp(ThemeExtension<CoolPalette>? other, double t) {
    if (other is! CoolPalette) {
      return this;
    }

    return CoolPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      border2: Color.lerp(border2, other.border2, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accent2: Color.lerp(accent2, other.accent2, t)!,
      accentGlow: Color.lerp(accentGlow, other.accentGlow, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      blueGlow: Color.lerp(blueGlow, other.blueGlow, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      red: Color.lerp(red, other.red, t)!,
    );
  }
}

extension CoolPaletteBuildContext on BuildContext {
  CoolPalette get coolPalette {
    final theme = Theme.of(this);
    return theme.extension<CoolPalette>() ??
        (theme.brightness == Brightness.light
            ? CoolPalette.light
            : CoolPalette.dark);
  }
}
