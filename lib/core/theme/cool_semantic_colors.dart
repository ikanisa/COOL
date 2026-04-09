part of 'cool_foundations.dart';

@immutable
class CoolSemanticColors extends ThemeExtension<CoolSemanticColors> {
  const CoolSemanticColors({
    required this.appBackground,
    required this.elevatedBackground,
    required this.cardSurface,
    required this.cardSurfaceStrong,
    required this.glassSurface,
    required this.overlaySurface,
    required this.primaryText,
    required this.secondaryText,
    required this.tertiaryText,
    required this.accent,
    required this.accentDeep,
    required this.accentStrong,
    required this.accentForeground,
    required this.accentGold,
    required this.divider,
    required this.border,
    required this.borderStrong,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
    required this.chipBackground,
    required this.chipSelectedBackground,
    required this.buttonPrimaryBackground,
    required this.buttonSecondaryBackground,
    required this.inputSurface,
    required this.shadowColor,
    required this.highlightColor,
  });

  static const CoolSemanticColors dark = CoolSemanticColors(
    // ── Surface hierarchy (violet monolith) ────────────────────────────
    appBackground: Color(0xFF0D0A27),        // Layer 0: infinite void
    elevatedBackground: Color(0xFF110E2D),   // surface_dim
    cardSurface: Color(0xFF1A1640),          // Layer 1: structural sections
    cardSurfaceStrong: Color(0xFF252054),     // Layer 2: interactive cards/hover
    glassSurface: Color(0x992A2555),          // 60% of surface_bright — frosted violet
    overlaySurface: Color(0xFF1A1640),        // Match Layer 1 for sheets/dialogs

    // ── Typography ─────────────────────────────────────────────────────
    primaryText: Color(0xFFF7F9FC),
    secondaryText: Color(0xFF8B8A9E),
    tertiaryText: Color(0xFF5E5C77),

    // ── Accent (primary as light source) ───────────────────────────────
    accent: Color(0xFF8781FF),               // primary_container
    accentDeep: Color(0xFF6C63FF),           // electric violet — hero gradients
    accentStrong: Color(0xFFC4C0FF),         // primary — the light source
    accentForeground: Color(0xFFFFFFFF),
    accentGold: Color(0xFFFACC15),

    // ── Boundaries (No-Line Rule) ──────────────────────────────────────
    divider: Color(0x00FFFFFF),              // Invisible — no divider lines
    border: Color(0x00FFFFFF),               // Invisible — no 1px borders
    borderStrong: Color(0x268781FF),          // Ghost border: violet at 15%

    // ── Semantic status ────────────────────────────────────────────────
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    info: Color(0xFF3B82F6),
    neutral: Color(0xFF8B8A9E),

    // ── Component tokens ───────────────────────────────────────────────
    chipBackground: Color(0xFF252054),       // secondary_container — pebble
    chipSelectedBackground: Color(0xFF8781FF),
    buttonPrimaryBackground: Color(0xFF8781FF), // primary_container — clay CTA
    buttonSecondaryBackground: Color(0x332A2555), // glass secondary
    inputSurface: Color(0xFF0D0A27),         // Sunken into surface_container_lowest
    shadowColor: Color(0xFF0D0A27),          // Desaturated void — never pure black
    highlightColor: Color(0x14C4C0FF),       // Primary highlight tint
  );

  static const CoolSemanticColors light = CoolSemanticColors(
    appBackground: Color(0xFFF4F7FB),
    elevatedBackground: Color(0xFFFFFFFF),
    cardSurface: Color(0xFFF8FAFD),
    cardSurfaceStrong: Color(0xFFFFFFFF),
    glassSurface: Color(0xE6FFFFFF),
    overlaySurface: Color(0xFFFFFFFF),
    primaryText: Color(0xFF0B1220),
    secondaryText: Color(0xFF475467),
    tertiaryText: Color(0xFF667085),
    accent: Color(0xFF0047AB),
    accentDeep: Color(0xFF003D96),
    accentStrong: Color(0xFF0C64D9),
    accentForeground: Color(0xFFFFFFFF),
    accentGold: Color(0xFFFFD700),
    divider: Color(0x140B1220),
    border: Color(0x140B1220),
    borderStrong: Color(0x330B1220),
    success: Color(0xFF0E9F6E),
    warning: Color(0xFFC97A00),
    danger: Color(0xFFD92D20),
    info: Color(0xFF2E90FA),
    neutral: Color(0xFF98A2B3),
    chipBackground: Color(0xFFE9EEF5),
    chipSelectedBackground: Color(0xFFDDE8FF),
    buttonPrimaryBackground: Color(0xFF0047AB),
    buttonSecondaryBackground: Color(0x120B1220),
    inputSurface: Color(0xFFF1F5F9),
    shadowColor: Color(0xFF0B1220),
    highlightColor: Color(0xFF0B1220),
  );

  final Color appBackground;
  final Color elevatedBackground;
  final Color cardSurface;
  final Color cardSurfaceStrong;
  final Color glassSurface;
  final Color overlaySurface;
  final Color primaryText;
  final Color secondaryText;
  final Color tertiaryText;
  final Color accent;
  final Color accentDeep;
  final Color accentStrong;
  final Color accentForeground;
  final Color accentGold;
  final Color divider;
  final Color border;
  final Color borderStrong;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color neutral;
  final Color chipBackground;
  final Color chipSelectedBackground;
  final Color buttonPrimaryBackground;
  final Color buttonSecondaryBackground;
  final Color inputSurface;
  final Color shadowColor;
  final Color highlightColor;

  Color get bg => appBackground;
  Color get surface => elevatedBackground;
  Color get surface2 => cardSurface;
  Color get surface3 => cardSurfaceStrong;
  Color get border2 => borderStrong;
  Color get text => primaryText;
  Color get text2 => secondaryText;
  Color get text3 => tertiaryText;
  Color get accent2 => accentStrong;
  Color get accentGlow => accentStrong.withValues(alpha: 0.16);
  Color get blue => info;
  Color get orange => warning;
  Color get red => danger;
  Color get yellow => warning;
  Color get purple => chipBackground;

  bool get _isDarkVariant => appBackground.computeLuminance() < 0.15;

  Color get operationalSurface =>
      _isDarkVariant ? const Color(0xFF110E2D) : const Color(0xFFF4F6FA);
  Color get financialSurface =>
      _isDarkVariant ? const Color(0xFF130F30) : const Color(0xFFF1F6FF);
  Color get analyticsSurface =>
      _isDarkVariant ? const Color(0xFF131035) : const Color(0xFFF1F7F8);
  Color get teamSurface =>
      _isDarkVariant ? const Color(0xFF150F30) : const Color(0xFFF7F3FF);
  Color get commerceSurface =>
      _isDarkVariant ? const Color(0xFF16102A) : const Color(0xFFFFF6EF);
  Color get routeSurface =>
      _isDarkVariant ? const Color(0xFF120E30) : const Color(0xFFF0F5FF);
  Color get proximitySurface =>
      _isDarkVariant ? const Color(0xFF100E2D) : const Color(0xFFF2FAF7);
  Color get contactSurface =>
      _isDarkVariant ? const Color(0xFF150F2A) : const Color(0xFFFFF9F0);

  Color get demandHigh => danger;
  Color get demandMedium => warning;
  Color get demandLow => success;

  Color get shellGradientTop => elevatedBackground;
  Color get shellGradientBottom => appBackground;
  Color get surfaceGradientTop => cardSurfaceStrong;
  Color get surfaceGradientBottom => cardSurface;
  Color get accentGradientStart => accentStrong;
  Color get accentGradientEnd => accent;

  /// The Tactile Monolith hero gradient — 4-stop claymorphic gradient
  /// anchored on the token surface hierarchy and accent pair.
  LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[cardSurface, accent, accentDeep, cardSurfaceStrong],
    stops: const <double>[0.0, 0.35, 0.70, 1.0],
  );

  LinearGradient get shellGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[shellGradientTop, shellGradientBottom],
  );

  LinearGradient get surfaceGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[surfaceGradientTop, surfaceGradientBottom],
  );

  LinearGradient get accentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[accentGradientStart, accentGradientEnd],
  );

  @override
  CoolSemanticColors copyWith({
    Color? appBackground,
    Color? elevatedBackground,
    Color? cardSurface,
    Color? cardSurfaceStrong,
    Color? glassSurface,
    Color? overlaySurface,
    Color? primaryText,
    Color? secondaryText,
    Color? tertiaryText,
    Color? accent,
    Color? accentDeep,
    Color? accentStrong,
    Color? accentForeground,
    Color? accentGold,
    Color? divider,
    Color? border,
    Color? borderStrong,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? neutral,
    Color? chipBackground,
    Color? chipSelectedBackground,
    Color? buttonPrimaryBackground,
    Color? buttonSecondaryBackground,
    Color? inputSurface,
    Color? shadowColor,
    Color? highlightColor,
  }) {
    return CoolSemanticColors(
      appBackground: appBackground ?? this.appBackground,
      elevatedBackground: elevatedBackground ?? this.elevatedBackground,
      cardSurface: cardSurface ?? this.cardSurface,
      cardSurfaceStrong: cardSurfaceStrong ?? this.cardSurfaceStrong,
      glassSurface: glassSurface ?? this.glassSurface,
      overlaySurface: overlaySurface ?? this.overlaySurface,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      tertiaryText: tertiaryText ?? this.tertiaryText,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      accentStrong: accentStrong ?? this.accentStrong,
      accentForeground: accentForeground ?? this.accentForeground,
      accentGold: accentGold ?? this.accentGold,
      divider: divider ?? this.divider,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      chipBackground: chipBackground ?? this.chipBackground,
      chipSelectedBackground:
          chipSelectedBackground ?? this.chipSelectedBackground,
      buttonPrimaryBackground:
          buttonPrimaryBackground ?? this.buttonPrimaryBackground,
      buttonSecondaryBackground:
          buttonSecondaryBackground ?? this.buttonSecondaryBackground,
      inputSurface: inputSurface ?? this.inputSurface,
      shadowColor: shadowColor ?? this.shadowColor,
      highlightColor: highlightColor ?? this.highlightColor,
    );
  }

  @override
  CoolSemanticColors lerp(ThemeExtension<CoolSemanticColors>? other, double t) {
    if (other is! CoolSemanticColors) return this;

    return CoolSemanticColors(
      appBackground: Color.lerp(appBackground, other.appBackground, t)!,
      elevatedBackground: Color.lerp(
        elevatedBackground,
        other.elevatedBackground,
        t,
      )!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      cardSurfaceStrong: Color.lerp(
        cardSurfaceStrong,
        other.cardSurfaceStrong,
        t,
      )!,
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      overlaySurface: Color.lerp(overlaySurface, other.overlaySurface, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      tertiaryText: Color.lerp(tertiaryText, other.tertiaryText, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      accentGold: Color.lerp(accentGold, other.accentGold, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      chipBackground: Color.lerp(chipBackground, other.chipBackground, t)!,
      chipSelectedBackground: Color.lerp(
        chipSelectedBackground,
        other.chipSelectedBackground,
        t,
      )!,
      buttonPrimaryBackground: Color.lerp(
        buttonPrimaryBackground,
        other.buttonPrimaryBackground,
        t,
      )!,
      buttonSecondaryBackground: Color.lerp(
        buttonSecondaryBackground,
        other.buttonSecondaryBackground,
        t,
      )!,
      inputSurface: Color.lerp(inputSurface, other.inputSurface, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      highlightColor: Color.lerp(highlightColor, other.highlightColor, t)!,
    );
  }
}
