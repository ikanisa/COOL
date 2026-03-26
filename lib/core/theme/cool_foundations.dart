import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

export 'cool_palette.dart';
export 'package:google_fonts/google_fonts.dart';

/// Next-generation semantic tokens for the production redesign.
///
/// These tokens sit alongside [CoolPalette] so the app can migrate screen by
/// screen without destabilizing the current production theme.
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
    required this.accentStrong,
    required this.accentForeground,
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
    required this.operationalSurface,
    required this.financialSurface,
    required this.analyticsSurface,
    required this.teamSurface,
    required this.commerceSurface,
    required this.routeSurface,
    required this.proximitySurface,
    required this.contactSurface,
    required this.demandHigh,
    required this.demandMedium,
    required this.demandLow,
    required this.shellGradientTop,
    required this.shellGradientBottom,
    required this.surfaceGradientTop,
    required this.surfaceGradientBottom,
    required this.accentGradientStart,
    required this.accentGradientEnd,
    required this.shadowColor,
    required this.highlightColor,
  });

  static const CoolSemanticColors light = CoolSemanticColors(
    appBackground: Color(0xFFF3F0EA),
    elevatedBackground: Color(0xFFFCFAF6),
    cardSurface: Color(0xFFF7F2EA),
    cardSurfaceStrong: Color(0xFFFFFDF9),
    glassSurface: Color(0xD6FFF8F0),
    overlaySurface: Color(0xFFFBF8F2),
    primaryText: Color(0xFF0B0F0D),
    secondaryText: Color(0xFF465147),
    tertiaryText: Color(0xFF6D776E),
    accent: Color(0xFF0047AB),
    accentStrong: Color(0xFF0C64D9),
    accentForeground: Color(0xFFFFFFFF),
    divider: Color(0x140B0F0D),
    border: Color(0x1F0B0F0D),
    borderStrong: Color(0x300B0F0D),
    success: Color(0xFF3FA06D),
    warning: Color(0xFFD09A4D),
    danger: Color(0xFFD0727A),
    info: Color(0xFF7E9CBC),
    neutral: Color(0xFF98A199),
    chipBackground: Color(0xFFF7F2EA),
    chipSelectedBackground: Color(0xFFFFFFFF),
    buttonPrimaryBackground: Color(0xFF0047AB),
    buttonSecondaryBackground: Color(0xFFF7F2EA),
    inputSurface: Color(0xFFFFFFFF),
    operationalSurface: Color(0xFFF1ECE4),
    financialSurface: Color(0xFFF5EFE6),
    analyticsSurface: Color(0xFFF3EEE8),
    teamSurface: Color(0xFFF3EDF6),
    commerceSurface: Color(0xFFF6F1EA),
    routeSurface: Color(0xFFF0EADF),
    proximitySurface: Color(0xFFF1EEE7),
    contactSurface: Color(0xFFEDE7DD),
    demandHigh: Color(0xFFD0727A),
    demandMedium: Color(0xFFD09A4D),
    demandLow: Color(0xFF58A67B),
    shellGradientTop: Color(0xFFFFFDF9),
    shellGradientBottom: Color(0xFFF0EBE2),
    surfaceGradientTop: Color(0xFFFFFFFF),
    surfaceGradientBottom: Color(0xFFF3EEE7),
    accentGradientStart: Color(0xFF0C64D9),
    accentGradientEnd: Color(0xFF003A90),
    shadowColor: Color(0xFF15120F),
    highlightColor: Color(0xFFFFFFFF),
  );

  static const CoolSemanticColors dark = CoolSemanticColors(
    appBackground: Color(0xFF050505),
    elevatedBackground: Color(0xFF0A0A0A),
    cardSurface: Color(0xFF111111),
    cardSurfaceStrong: Color(0xFF171717),
    glassSurface: Color(0xCC0A0A0A),
    overlaySurface: Color(0xFF0B0B0B),
    primaryText: Color(0xFFFFFFFF),
    secondaryText: Color(0xFFB4B4B4),
    tertiaryText: Color(0xFF808080),
    accent: Color(0xFF0047AB),
    accentStrong: Color(0xFF0C64D9),
    accentForeground: Color(0xFFFFFFFF),
    divider: Color(0x14FFFFFF),
    border: Color(0x1FFFFFFF),
    borderStrong: Color(0x33FFFFFF),
    success: Color(0xFF00C26E),
    warning: Color(0xFFFFB547),
    danger: Color(0xFFFF5B55),
    info: Color(0xFF74A8FF),
    neutral: Color(0xFF909B91),
    chipBackground: Color(0xFF141414),
    chipSelectedBackground: Color(0xFFFFFFFF),
    buttonPrimaryBackground: Color(0xFF0047AB),
    buttonSecondaryBackground: Color(0xFF161616),
    inputSurface: Color(0xFF121212),
    operationalSurface: Color(0xFF0F1115),
    financialSurface: Color(0xFF0D111A),
    analyticsSurface: Color(0xFF11131A),
    teamSurface: Color(0xFF151320),
    commerceSurface: Color(0xFF151311),
    routeSurface: Color(0xFF101215),
    proximitySurface: Color(0xFF0E1310),
    contactSurface: Color(0xFF0F1513),
    demandHigh: Color(0xFFFF5B55),
    demandMedium: Color(0xFFFFB547),
    demandLow: Color(0xFF00C26E),
    shellGradientTop: Color(0xFF0A0A0A),
    shellGradientBottom: Color(0xFF020202),
    surfaceGradientTop: Color(0xFF171717),
    surfaceGradientBottom: Color(0xFF0C0C0C),
    accentGradientStart: Color(0xFF0C64D9),
    accentGradientEnd: Color(0xFF003C92),
    shadowColor: Color(0xFF000000),
    highlightColor: Color(0xFFFFFFFF),
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
  final Color accentStrong;
  final Color accentForeground;
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
  final Color operationalSurface;
  final Color financialSurface;
  final Color analyticsSurface;
  final Color teamSurface;
  final Color commerceSurface;
  final Color routeSurface;
  final Color proximitySurface;
  final Color contactSurface;
  final Color demandHigh;
  final Color demandMedium;
  final Color demandLow;
  final Color shellGradientTop;
  final Color shellGradientBottom;
  final Color surfaceGradientTop;
  final Color surfaceGradientBottom;
  final Color accentGradientStart;
  final Color accentGradientEnd;
  final Color shadowColor;
  final Color highlightColor;

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

  // Legacy alias getters to keep partial migrations compiling.
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
  Color get purple => teamSurface;

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
    Color? accentStrong,
    Color? accentForeground,
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
    Color? operationalSurface,
    Color? financialSurface,
    Color? analyticsSurface,
    Color? teamSurface,
    Color? commerceSurface,
    Color? routeSurface,
    Color? proximitySurface,
    Color? contactSurface,
    Color? demandHigh,
    Color? demandMedium,
    Color? demandLow,
    Color? shellGradientTop,
    Color? shellGradientBottom,
    Color? surfaceGradientTop,
    Color? surfaceGradientBottom,
    Color? accentGradientStart,
    Color? accentGradientEnd,
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
      accentStrong: accentStrong ?? this.accentStrong,
      accentForeground: accentForeground ?? this.accentForeground,
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
      operationalSurface: operationalSurface ?? this.operationalSurface,
      financialSurface: financialSurface ?? this.financialSurface,
      analyticsSurface: analyticsSurface ?? this.analyticsSurface,
      teamSurface: teamSurface ?? this.teamSurface,
      commerceSurface: commerceSurface ?? this.commerceSurface,
      routeSurface: routeSurface ?? this.routeSurface,
      proximitySurface: proximitySurface ?? this.proximitySurface,
      contactSurface: contactSurface ?? this.contactSurface,
      demandHigh: demandHigh ?? this.demandHigh,
      demandMedium: demandMedium ?? this.demandMedium,
      demandLow: demandLow ?? this.demandLow,
      shellGradientTop: shellGradientTop ?? this.shellGradientTop,
      shellGradientBottom: shellGradientBottom ?? this.shellGradientBottom,
      surfaceGradientTop: surfaceGradientTop ?? this.surfaceGradientTop,
      surfaceGradientBottom:
          surfaceGradientBottom ?? this.surfaceGradientBottom,
      accentGradientStart: accentGradientStart ?? this.accentGradientStart,
      accentGradientEnd: accentGradientEnd ?? this.accentGradientEnd,
      shadowColor: shadowColor ?? this.shadowColor,
      highlightColor: highlightColor ?? this.highlightColor,
    );
  }

  @override
  CoolSemanticColors lerp(ThemeExtension<CoolSemanticColors>? other, double t) {
    if (other is! CoolSemanticColors) {
      return this;
    }

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
      accentStrong: Color.lerp(accentStrong, other.accentStrong, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
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
      operationalSurface: Color.lerp(
        operationalSurface,
        other.operationalSurface,
        t,
      )!,
      financialSurface: Color.lerp(
        financialSurface,
        other.financialSurface,
        t,
      )!,
      analyticsSurface: Color.lerp(
        analyticsSurface,
        other.analyticsSurface,
        t,
      )!,
      teamSurface: Color.lerp(teamSurface, other.teamSurface, t)!,
      commerceSurface: Color.lerp(commerceSurface, other.commerceSurface, t)!,
      routeSurface: Color.lerp(routeSurface, other.routeSurface, t)!,
      proximitySurface: Color.lerp(
        proximitySurface,
        other.proximitySurface,
        t,
      )!,
      contactSurface: Color.lerp(contactSurface, other.contactSurface, t)!,
      demandHigh: Color.lerp(demandHigh, other.demandHigh, t)!,
      demandMedium: Color.lerp(demandMedium, other.demandMedium, t)!,
      demandLow: Color.lerp(demandLow, other.demandLow, t)!,
      shellGradientTop: Color.lerp(
        shellGradientTop,
        other.shellGradientTop,
        t,
      )!,
      shellGradientBottom: Color.lerp(
        shellGradientBottom,
        other.shellGradientBottom,
        t,
      )!,
      surfaceGradientTop: Color.lerp(
        surfaceGradientTop,
        other.surfaceGradientTop,
        t,
      )!,
      surfaceGradientBottom: Color.lerp(
        surfaceGradientBottom,
        other.surfaceGradientBottom,
        t,
      )!,
      accentGradientStart: Color.lerp(
        accentGradientStart,
        other.accentGradientStart,
        t,
      )!,
      accentGradientEnd: Color.lerp(
        accentGradientEnd,
        other.accentGradientEnd,
        t,
      )!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      highlightColor: Color.lerp(highlightColor, other.highlightColor, t)!,
    );
  }
}

/// Typography helpers that keep migrations anchored to [TextTheme] while
/// allowing approved mono and Rayon brand overrides.
@immutable
class CoolTextStyles {
  const CoolTextStyles._({
    required TextTheme textTheme,
    required Color defaultColor,
  }) : _textTheme = textTheme,
       _defaultColor = defaultColor;

  final TextTheme _textTheme;
  final Color _defaultColor;

  TextTheme get theme => _textTheme;

  TextStyle mono(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.bodyLarge ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    return GoogleFonts.dmMono(
      textStyle: resolvedBase.copyWith(
        color: color ?? resolvedBase.color ?? _defaultColor,
        fontWeight: fontWeight ?? resolvedBase.fontWeight,
        letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
        height: height ?? resolvedBase.height,
      ),
    );
  }

  /// Large hero number for financial dashboards (MoMo balance, group totals).
  ///
  /// BarlowCondensed 56px, w900, tight height for stamp-like impact.
  TextStyle heroNumber({Color? color}) {
    return GoogleFonts.barlowCondensed(
      textStyle: TextStyle(
        fontSize: 56,
        fontWeight: FontWeight.w900,
        color: color ?? _defaultColor,
        letterSpacing: -3.0,
        height: 0.9,
      ),
    );
  }

  TextStyle rayon(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.bodyLarge ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    return GoogleFonts.barlow(
      textStyle: resolvedBase.copyWith(
        color: color ?? resolvedBase.color ?? _defaultColor,
        fontWeight: fontWeight ?? resolvedBase.fontWeight,
        letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
        height: height ?? resolvedBase.height,
      ),
    );
  }

  TextStyle rayonCondensed(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.titleLarge ??
        const TextStyle(fontSize: 24, fontWeight: FontWeight.w800);
    return GoogleFonts.barlowCondensed(
      textStyle: resolvedBase.copyWith(
        color: color ?? resolvedBase.color ?? _defaultColor,
        fontWeight: fontWeight ?? resolvedBase.fontWeight,
        letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
        height: height ?? resolvedBase.height,
      ),
    );
  }
}

@immutable
class CoolSpaceTokens {
  const CoolSpaceTokens._();

  double get x0 => CoolSpace.x0;
  double get x1 => CoolSpace.x1;
  double get x2 => CoolSpace.x2;
  double get x3 => CoolSpace.x3;
  double get x4 => CoolSpace.x4;
  double get x5 => CoolSpace.x5;
  double get x6 => CoolSpace.x6;
  double get x7 => CoolSpace.x7;
  double get x8 => CoolSpace.x8;
  double get x9 => CoolSpace.x9;
  double get x10 => CoolSpace.x10;
  double get x12 => CoolSpace.x12;
  double get x16 => CoolSpace.x16;

  EdgeInsets get pagePadding => CoolSpace.pagePadding;
  EdgeInsets get sectionPadding => CoolSpace.sectionPadding;
  EdgeInsets get denseSectionPadding => CoolSpace.denseSectionPadding;
  EdgeInsets get scaffoldPadding => CoolSpace.scaffoldPadding;
}

@immutable
class CoolRadiiTokens {
  const CoolRadiiTokens._();

  double get xs => CoolRadii.xs;
  double get sm => CoolRadii.sm;
  double get md => CoolRadii.md;
  double get lg => CoolRadii.lg;
  double get xl => CoolRadii.xl;
  double get xxl => CoolRadii.xxl;
  double get pill => CoolRadii.pill;
}

@immutable
class CoolInsetsTokens {
  const CoolInsetsTokens._();

  EdgeInsets all(double value) => EdgeInsets.all(value);

  EdgeInsets symmetric({double horizontal = 0, double vertical = 0}) =>
      EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);

  EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) => EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);

  EdgeInsets fromLTRB(double left, double top, double right, double bottom) =>
      EdgeInsets.fromLTRB(left, top, right, bottom);

  EdgeInsets get zero => EdgeInsets.zero;
  EdgeInsets get pagePadding => CoolSpace.pagePadding;
  EdgeInsets get sectionPadding => CoolSpace.sectionPadding;
  EdgeInsets get denseSectionPadding => CoolSpace.denseSectionPadding;
  EdgeInsets get scaffoldPadding => CoolSpace.scaffoldPadding;
}

extension CoolSemanticColorsBuildContext on BuildContext {
  CoolSemanticColors get coolSemanticColors {
    final theme = Theme.of(this);
    return theme.extension<CoolSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? CoolSemanticColors.dark
            : CoolSemanticColors.light);
  }

  CoolTextStyles get coolText => CoolTextStyles._(
    textTheme: Theme.of(this).textTheme,
    defaultColor: coolSemanticColors.primaryText,
  );

  CoolSpaceTokens get coolSpace => const CoolSpaceTokens._();

  CoolRadiiTokens get coolRadii => const CoolRadiiTokens._();

  CoolInsetsTokens get coolInsets => const CoolInsetsTokens._();
}

/// Shared spacing scale for the redesign rollout.
abstract final class CoolSpace {
  static const double x0 = 0.0;
  static const double x1 = 4.0;
  static const double x2 = 8.0;
  static const double x3 = 12.0;
  static const double x4 = 16.0;
  static const double x5 = 20.0;
  static const double x6 = 24.0;
  static const double x7 = 32.0;
  static const double x8 = 40.0;
  static const double x9 = 48.0;
  static const double x10 = 64.0;
  static const double x12 = x3;
  static const double x16 = 88.0;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: x6,
    vertical: x6,
  );

  static const EdgeInsets sectionPadding = EdgeInsets.all(x6);
  static const EdgeInsets denseSectionPadding = EdgeInsets.all(x5);
  static const EdgeInsets scaffoldPadding = EdgeInsets.fromLTRB(x6, 0, x6, 96);
}

/// Shared radii for redesign components.
abstract final class CoolRadii {
  static const double xs = 12.0;
  static const double sm = 16.0;
  static const double md = 22.0;
  static const double lg = 28.0;
  static const double xl = 32.0;
  static const double xxl = 36.0;
  static const double pill = 999.0;
}

/// Blur guidance for glass surfaces.
///
/// Increased sigma values (inspired by Mobio σ30) for heavier frosted glass.
abstract final class CoolBlur {
  static const double subtle = 14.0;
  static const double standard = 24.0;
  static const double overlay = 28.0;
  static const double heavy = overlay;
}

/// Per-mode opacity tokens for glass and clay surfaces.
///
/// Inspired by Mobio's explicit per-mode alpha tuning.
abstract final class CoolGlassOpacity {
  // ── Glass card ──────────────────────────────────────────────────────
  static double glassBackground(Brightness brightness) =>
      brightness == Brightness.dark ? 0.76 : 0.82;

  static double glassBorderWhite(Brightness brightness) =>
      brightness == Brightness.dark ? 0.08 : 0.18;

  static double glassGradientWhite(Brightness brightness) =>
      brightness == Brightness.dark ? 0.05 : 0.12;

  // ── Clay card ──────────────────────────────────────────────────────
  static double clayGradientWhite(Brightness brightness) =>
      brightness == Brightness.dark ? 0.03 : 0.12;
}

/// Elevation guidance for the redesign.
abstract final class CoolElevation {
  static const double resting = 0.0;
  static const double raised = 8.0;
  static const double floating = 12.0;
  static const double overlay = 16.0;
}

/// Touch-target standards used across consumer and admin surfaces.
abstract final class CoolTapTargets {
  static const double minimum = 48.0;
  static const double comfortable = 56.0;
  static const double navigation = 64.0;
}

/// Motion primitives for calmer, higher-trust interactions.
abstract final class CoolMotion {
  static const Duration press = Duration(milliseconds: 110);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration medium = standard;
  static const Duration emphasized = Duration(milliseconds: 300);

  static const Curve enterCurve = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve exitCurve = Cubic(0.4, 0.0, 1.0, 1.0);
  static const Curve pressCurve = Curves.easeInOut;
}

/// Responsive helpers that keep the redesign mobile-first.
abstract final class CoolResponsive {
  static double horizontalPaddingForWidth(double width) {
    if (width >= 840) {
      return 40.0;
    }
    if (width >= 600) {
      return 32.0;
    }
    return 24.0;
  }

  static double maxContentWidthForWidth(double width) {
    if (width >= 840) {
      return 720.0;
    }
    return width;
  }
}

/// Shadow recipes for clay, floating, and glass surfaces.
///
/// Light-mode values refined for softer appearance (Mobio-inspired per-mode tuning).
abstract final class CoolShadows {
  static List<BoxShadow> clay(Brightness brightness, {double strength = 1}) {
    final bool isDark = brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(
          alpha: (isDark ? 0.42 : 0.08) * strength,
        ),
        blurRadius: 40,
        spreadRadius: -18,
        offset: const Offset(0, 24),
      ),
    ];
  }

  static List<BoxShadow> glass(Brightness brightness, {double strength = 1}) {
    final bool isDark = brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(
          alpha: (isDark ? 0.40 : 0.10) * strength,
        ),
        blurRadius: 48,
        spreadRadius: -22,
        offset: const Offset(0, 28),
      ),
    ];
  }

  static List<BoxShadow> floating(
    Brightness brightness, {
    double strength = 1,
  }) {
    final bool isDark = brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(
          alpha: (isDark ? 0.46 : 0.10) * strength,
        ),
        blurRadius: 52,
        spreadRadius: -24,
        offset: const Offset(0, 30),
      ),
    ];
  }
}
