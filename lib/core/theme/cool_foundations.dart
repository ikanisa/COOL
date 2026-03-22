import 'package:flutter/material.dart';

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
    glassSurface: Color(0xD6FFFCF7),
    overlaySurface: Color(0xFFFBF8F2),
    primaryText: Color(0xFF0B0F0D),
    secondaryText: Color(0xFF465147),
    tertiaryText: Color(0xFF6D776E),
    accent: Color(0xFF2F7252),
    accentStrong: Color(0xFF103322),
    accentForeground: Color(0xFFF8F5EE),
    divider: Color(0x140B0F0D),
    border: Color(0x1F0B0F0D),
    borderStrong: Color(0x2E0B0F0D),
    success: Color(0xFF2F7252),
    warning: Color(0xFFA86F26),
    danger: Color(0xFFA24C54),
    info: Color(0xFF4C6886),
    neutral: Color(0xFF737B74),
    chipBackground: Color(0xFFF1ECE3),
    chipSelectedBackground: Color(0xFFE2F0E8),
    buttonPrimaryBackground: Color(0xFF2F7252),
    buttonSecondaryBackground: Color(0xFFFCFAF6),
    inputSurface: Color(0xFFFEFBF8),
    operationalSurface: Color(0xFFEEF2F0),
    financialSurface: Color(0xFFEDF4EF),
    analyticsSurface: Color(0xFFEEF1F5),
    teamSurface: Color(0xFFF1EEF6),
    commerceSurface: Color(0xFFF5F0E8),
    routeSurface: Color(0xFFF1ECE4),
    proximitySurface: Color(0xFFE7F0EA),
    contactSurface: Color(0xFFEAF3ED),
    demandHigh: Color(0xFFA24C54),
    demandMedium: Color(0xFFA86F26),
    demandLow: Color(0xFF2F7252),
    shellGradientTop: Color(0xFFFAF7F2),
    shellGradientBottom: Color(0xFFECE5DA),
    surfaceGradientTop: Color(0xFFFFFDF9),
    surfaceGradientBottom: Color(0xFFF2ECE3),
    accentGradientStart: Color(0xFF2F7252),
    accentGradientEnd: Color(0xFF103322),
    shadowColor: Color(0xFF000000),
    highlightColor: Color(0xFFFFFFFF),
  );

  static const CoolSemanticColors dark = CoolSemanticColors(
    appBackground: Color(0xFF070B09),
    elevatedBackground: Color(0xFF0D110E),
    cardSurface: Color(0xFF141A16),
    cardSurfaceStrong: Color(0xFF1B221D),
    glassSurface: Color(0xD1111713),
    overlaySurface: Color(0xFF111713),
    primaryText: Color(0xFFF4F1E9),
    secondaryText: Color(0xFFC4CBC2),
    tertiaryText: Color(0xFF909B91),
    accent: Color(0xFF3A8A5E),
    accentStrong: Color(0xFF173726),
    accentForeground: Color(0xFFF7F3EA),
    divider: Color(0x14FFFFFF),
    border: Color(0x1FFFFFFF),
    borderStrong: Color(0x33FFFFFF),
    success: Color(0xFF58A67B),
    warning: Color(0xFFD09A4D),
    danger: Color(0xFFD0727A),
    info: Color(0xFF7E9CBC),
    neutral: Color(0xFF98A199),
    chipBackground: Color(0xFF171E19),
    chipSelectedBackground: Color(0xFF1D3629),
    buttonPrimaryBackground: Color(0xFF3A8A5E),
    buttonSecondaryBackground: Color(0xFF141A16),
    inputSurface: Color(0xFF121814),
    operationalSurface: Color(0xFF0F1814),
    financialSurface: Color(0xFF0E1712),
    analyticsSurface: Color(0xFF101721),
    teamSurface: Color(0xFF151320),
    commerceSurface: Color(0xFF1A1713),
    routeSurface: Color(0xFF121814),
    proximitySurface: Color(0xFF0E1813),
    contactSurface: Color(0xFF10201A),
    demandHigh: Color(0xFFD0727A),
    demandMedium: Color(0xFFD09A4D),
    demandLow: Color(0xFF58A67B),
    shellGradientTop: Color(0xFF141915),
    shellGradientBottom: Color(0xFF060806),
    surfaceGradientTop: Color(0xFF1A211C),
    surfaceGradientBottom: Color(0xFF0E120F),
    accentGradientStart: Color(0xFF3A8A5E),
    accentGradientEnd: Color(0xFF173726),
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

extension CoolSemanticColorsBuildContext on BuildContext {
  CoolSemanticColors get coolSemanticColors {
    final theme = Theme.of(this);
    return theme.extension<CoolSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? CoolSemanticColors.dark
            : CoolSemanticColors.light);
  }
}

/// Shared spacing scale for the redesign rollout.
abstract final class CoolSpace {
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

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: x6,
    vertical: x6,
  );

  static const EdgeInsets sectionPadding = EdgeInsets.all(x6);
  static const EdgeInsets denseSectionPadding = EdgeInsets.all(x5);
}

/// Shared radii for redesign components.
abstract final class CoolRadii {
  static const double sm = 16.0;
  static const double md = 22.0;
  static const double lg = 28.0;
  static const double xl = 32.0;
  static const double xxl = 36.0;
  static const double pill = 999.0;
}

/// Blur guidance for glass surfaces.
abstract final class CoolBlur {
  static const double subtle = 12.0;
  static const double standard = 18.0;
  static const double overlay = 22.0;
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
abstract final class CoolShadows {
  static List<BoxShadow> clay(Brightness brightness, {double strength = 1}) {
    final bool isDark = brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(
          alpha: (isDark ? 0.34 : 0.10) * strength,
        ),
        blurRadius: 28,
        spreadRadius: -14,
        offset: const Offset(0, 18),
      ),
      BoxShadow(
        color: Colors.white.withValues(
          alpha: (isDark ? 0.05 : 0.68) * strength,
        ),
        blurRadius: 12,
        spreadRadius: -10,
        offset: const Offset(-3, -4),
      ),
    ];
  }

  static List<BoxShadow> glass(Brightness brightness, {double strength = 1}) {
    final bool isDark = brightness == Brightness.dark;
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(
          alpha: (isDark ? 0.26 : 0.10) * strength,
        ),
        blurRadius: 32,
        spreadRadius: -16,
        offset: const Offset(0, 18),
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
          alpha: (isDark ? 0.30 : 0.12) * strength,
        ),
        blurRadius: 36,
        spreadRadius: -18,
        offset: const Offset(0, 22),
      ),
    ];
  }
}
