import 'package:flutter/material.dart';

/// Theme-aware semantic color roles for the Cool app shell.
///
/// **DEPRECATED** — migrate to [CoolSemanticColors] via `context.coolSemanticColors`.
///
/// Migration mapping:
/// ```
/// coolPalette.bg       → sem.appBackground
/// coolPalette.surface  → sem.elevatedBackground
/// coolPalette.surface2 → sem.cardSurface
/// coolPalette.surface3 → sem.cardSurfaceStrong
/// coolPalette.border   → sem.border
/// coolPalette.border2  → sem.borderStrong
/// coolPalette.text     → sem.primaryText
/// coolPalette.text2    → sem.secondaryText
/// coolPalette.text3    → sem.tertiaryText
/// coolPalette.accent   → sem.accent
/// coolPalette.accent2  → sem.accentStrong
/// ```
@Deprecated(
  'Use CoolSemanticColors via context.coolSemanticColors instead. '
  'See migration mapping in doc comment above.',
)
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
    bg: Color(0xFF111413),
    surface: Color(0xFF151817),
    surface2: Color(0xFF191C1B),
    surface3: Color(0xFF333534),
    border: Color(0x14FFFFFF),
    border2: Color(0x26FFFFFF),
    text: Color(0xFFF3F5F1),
    text2: Color(0xFFC3CAC4),
    text3: Color(0xFF8C948D),
    accent: Color(0xFF0047AB),
    accent2: Color(0xFF003888),
    accentGlow: Color(0x290047AB),
    blue: Color(0xFF89AFFF),
    blueGlow: Color(0x2489AFFF),
    orange: Color(0xFFFFB59A),
    purple: Color(0xFF181822),
    yellow: Color(0xFFFFB59A),
    red: Color(0xFFD0727A),
  );

  static const light = CoolPalette(
    bg: Color(0xFFF1F3F0),
    surface: Color(0xFFF5F6F4),
    surface2: Color(0xFFE7EBE7),
    surface3: Color(0xFFFDFEFC),
    border: Color(0x16000000),
    border2: Color(0x26000000),
    text: Color(0xFF111413),
    text2: Color(0xFF4E5450),
    text3: Color(0xFF757D77),
    accent: Color(0xFF0047AB),
    accent2: Color(0xFF003A8C),
    accentGlow: Color(0x290047AB),
    blue: Color(0xFF54759A),
    blueGlow: Color(0x2454759A),
    orange: Color(0xFFFFB59A),
    purple: Color(0xFFE9E9F0),
    yellow: Color(0xFFFFB59A),
    red: Color(0xFFA24C54),
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
