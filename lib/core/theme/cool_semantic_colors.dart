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
    appBackground: Color(0xFF0F141B),
    elevatedBackground: Color(0xFF131A23),
    cardSurface: Color(0xFF18212B),
    cardSurfaceStrong: Color(0xFF202A36),
    glassSurface: Color(0xD9151D27),
    overlaySurface: Color(0xFF161E28),
    primaryText: Color(0xFFF6F8FB),
    secondaryText: Color(0xFF9BA7B4),
    tertiaryText: Color(0xFF6D7884),
    accent: Color(0xFF4D79FF),
    accentDeep: Color(0xFF305FE8),
    accentStrong: Color(0xFFDDE6FF),
    accentForeground: Color(0xFFFFFFFF),
    accentGold: Color(0xFFE6B353),
    divider: Color(0x1AFFFFFF),
    border: Color(0x1FFFFFFF),
    borderStrong: Color(0x2EFFFFFF),
    success: Color(0xFF23A26D),
    warning: Color(0xFFD39A2A),
    danger: Color(0xFFD95C5C),
    info: Color(0xFF4D79FF),
    neutral: Color(0xFF9BA7B4),
    chipBackground: Color(0xFF1E2732),
    chipSelectedBackground: Color(0xFF294C9F),
    buttonPrimaryBackground: Color(0xFF4D79FF),
    buttonSecondaryBackground: Color(0xFF202A36),
    inputSurface: Color(0xFF161F29),
    shadowColor: Color(0xFF09111F),
    highlightColor: Color(0x144D79FF),
  );

  static const CoolSemanticColors light = CoolSemanticColors(
    appBackground: Color(0xFFF3F5F7),
    elevatedBackground: Color(0xFFFFFFFF),
    cardSurface: Color(0xFFFFFFFF),
    cardSurfaceStrong: Color(0xFFF0F3F6),
    glassSurface: Color(0xEBFFFFFF),
    overlaySurface: Color(0xFFFFFFFF),
    primaryText: Color(0xFF111827),
    secondaryText: Color(0xFF5E6B7A),
    tertiaryText: Color(0xFF8A96A3),
    accent: Color(0xFF315EEA),
    accentDeep: Color(0xFF2446B9),
    accentStrong: Color(0xFFE3EBFF),
    accentForeground: Color(0xFFFFFFFF),
    accentGold: Color(0xFFB37A1A),
    divider: Color(0x1409111F),
    border: Color(0x1609111F),
    borderStrong: Color(0x2409111F),
    success: Color(0xFF1C8C5D),
    warning: Color(0xFFC28212),
    danger: Color(0xFFCC5757),
    info: Color(0xFF315EEA),
    neutral: Color(0xFF7B8794),
    chipBackground: Color(0xFFF0F3F6),
    chipSelectedBackground: Color(0xFFDDE6FF),
    buttonPrimaryBackground: Color(0xFF315EEA),
    buttonSecondaryBackground: Color(0xFFF0F3F6),
    inputSurface: Color(0xFFF6F8FA),
    shadowColor: Color(0xFF09111F),
    highlightColor: Color(0x14315EEA),
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
      _isDarkVariant ? const Color(0xFF151D26) : const Color(0xFFFFFFFF);
  Color get financialSurface =>
      _isDarkVariant ? const Color(0xFF17202A) : const Color(0xFFF7FAFF);
  Color get analyticsSurface =>
      _isDarkVariant ? const Color(0xFF16212B) : const Color(0xFFF6FAFB);
  Color get teamSurface =>
      _isDarkVariant ? const Color(0xFF19222D) : const Color(0xFFF8FAFC);
  Color get commerceSurface =>
      _isDarkVariant ? const Color(0xFF1A232D) : const Color(0xFFFFFAF3);
  Color get routeSurface =>
      _isDarkVariant ? const Color(0xFF16202A) : const Color(0xFFF5F8FF);
  Color get proximitySurface =>
      _isDarkVariant ? const Color(0xFF16212A) : const Color(0xFFF5FBF8);
  Color get contactSurface =>
      _isDarkVariant ? const Color(0xFF1A232C) : const Color(0xFFFFFBF6);

  Color get demandHigh => danger;
  Color get demandMedium => warning;
  Color get demandLow => success;

  Color get shellGradientTop => elevatedBackground;
  Color get shellGradientBottom => appBackground;
  Color get surfaceGradientTop => cardSurfaceStrong;
  Color get surfaceGradientBottom => cardSurface;
  Color get accentGradientStart => accentStrong;
  Color get accentGradientEnd => accent;

  LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[accent, accentDeep],
  );

  LinearGradient get shellGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[shellGradientTop, shellGradientBottom],
  );

  LinearGradient get surfaceGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
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
