import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

export 'package:google_fonts/google_fonts.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Mobi × Rayon Design System — Foundation Tokens
//
// Shared light/dark foundations for the production UI system.
// Dark remains the primary runtime presentation; light is maintained for
// design-system parity, widget adaptation, and test coverage.
// ──────────────────────────────────────────────────────────────────────────────

/// Production semantic color tokens — Mobi × Rayon system.
///
/// Access via `context.coolSemanticColors` or `CoolSemanticColors.dark`.
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
    appBackground: Color(0xFF050505), // true black
    elevatedBackground: Color(0xFF0A0A0A), // ink
    cardSurface: Color(0xFF111111), // surfaceAlt
    cardSurfaceStrong: Color(0xFF171717), // raised cards
    glassSurface: Color(0x0DFFFFFF), // white/5 + backdrop-blur
    overlaySurface: Color(0xFF0B0B0B), // modal surfaces
    primaryText: Color(0xFFFFFFFF), // pure white
    secondaryText: Color(0xFF888888), // muted gray
    tertiaryText: Color(0xFF666666), // subtle gray
    accent: Color(0xFF0047AB), // deep royal blue
    accentStrong: Color(0xFF0C64D9), // bright blue
    accentForeground: Color(0xFFFFFFFF), // white on accent
    accentGold: Color(0xFFFFD700), // gold
    divider: Color(0x14FFFFFF), // white/8
    border: Color(0x0DFFFFFF), // white/5 — subtle
    borderStrong: Color(0x33FFFFFF), // white/20 — hover/focus
    success: Color(0xFF00FF00), // neon green
    warning: Color(0xFFFFA500), // bright orange
    danger: Color(0xFFFF3B30), // iOS red
    info: Color(0xFF74A8FF), // soft blue
    neutral: Color(0xFF888888), // gray
    chipBackground: Color(0xFF141414), // slightly above surface
    chipSelectedBackground: Color(0xFFFFFFFF), // white
    buttonPrimaryBackground: Color(0xFF0047AB), // royal blue
    buttonSecondaryBackground: Color(0x1AFFFFFF), // white/10
    inputSurface: Color(0x0DFFFFFF), // white/5
    shadowColor: Color(0xFF000000), // pure black
    highlightColor: Color(0xFFFFFFFF), // pure white
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

  // ── Legacy alias getters (keep partial migrations compiling) ──────────

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
  Color get purple => chipBackground; // neutral surface

  bool get _isDarkVariant => appBackground.computeLuminance() < 0.15;

  // Keep domain surfaces visually close to the existing system while preserving
  // distinct semantic tones for dashboards, finance, routing, and partner UIs.
  Color get operationalSurface =>
      _isDarkVariant ? const Color(0xFF121212) : const Color(0xFFF4F6FA);
  Color get financialSurface =>
      _isDarkVariant ? const Color(0xFF11141A) : const Color(0xFFF1F6FF);
  Color get analyticsSurface =>
      _isDarkVariant ? const Color(0xFF11161A) : const Color(0xFFF1F7F8);
  Color get teamSurface =>
      _isDarkVariant ? const Color(0xFF141219) : const Color(0xFFF7F3FF);
  Color get commerceSurface =>
      _isDarkVariant ? const Color(0xFF15120F) : const Color(0xFFFFF6EF);
  Color get routeSurface =>
      _isDarkVariant ? const Color(0xFF10151A) : const Color(0xFFF0F5FF);
  Color get proximitySurface =>
      _isDarkVariant ? const Color(0xFF0F1517) : const Color(0xFFF2FAF7);
  Color get contactSurface =>
      _isDarkVariant ? const Color(0xFF141411) : const Color(0xFFFFF9F0);

  // ── Abolished demand colors — redirect to states ─────────────────────
  Color get demandHigh => danger;
  Color get demandMedium => warning;
  Color get demandLow => success;

  // ── Abolished gradient colors — kept as simple values ────────────────
  Color get shellGradientTop => elevatedBackground;
  Color get shellGradientBottom => appBackground;
  Color get surfaceGradientTop => cardSurfaceStrong;
  Color get surfaceGradientBottom => cardSurface;
  Color get accentGradientStart => accentStrong;
  Color get accentGradientEnd => accent;

  // ── Gradient helpers ─────────────────────────────────────────────────

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

// ──────────────────────────────────────────────────────────────────────────────
// Typography Helpers
// ──────────────────────────────────────────────────────────────────────────────

/// Typography helpers anchored to [TextTheme] with DM Mono and
/// Barlow Condensed overrides for values and headings.
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

  /// Monospace text — DM Mono for values, IDs, labels.
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

  /// mobi-label: 10px, DM Mono, uppercase, wide tracking.
  TextStyle mobiLabel({Color? color}) {
    final labelColor = _textTheme.labelSmall?.color ?? _defaultColor;
    return GoogleFonts.dmMono(
      textStyle: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color ?? labelColor,
        letterSpacing: 1.0,
        height: 1.2,
      ),
    );
  }

  /// mobi-value: 14px, DM Mono, tight tracking.
  TextStyle mobiValue({Color? color}) {
    return GoogleFonts.dmMono(
      textStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color ?? _defaultColor,
        letterSpacing: -0.28,
        height: 1.3,
      ),
    );
  }

  /// Large hero number for financial dashboards (MoMo balance, group totals).
  ///
  /// BarlowCondensed 48px, w900, tight height for stamp-like impact.
  TextStyle heroNumber({Color? color}) {
    return GoogleFonts.barlowCondensed(
      textStyle: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w900,
        color: color ?? _defaultColor,
        letterSpacing: -2.0,
        height: 0.9,
      ),
    );
  }

  /// Barlow body text for branded partner contexts.
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

  /// Barlow Condensed for uppercase headings.
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

// ──────────────────────────────────────────────────────────────────────────────
// Spacing Scale
// ──────────────────────────────────────────────────────────────────────────────

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

// ──────────────────────────────────────────────────────────────────────────────
// BuildContext Extensions
// ──────────────────────────────────────────────────────────────────────────────

extension CoolSemanticColorsBuildContext on BuildContext {
  CoolSemanticColors get coolSemanticColors {
    return Theme.of(this).extension<CoolSemanticColors>() ??
        (Theme.of(this).brightness == Brightness.dark
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

// ──────────────────────────────────────────────────────────────────────────────
// Spacing
// ──────────────────────────────────────────────────────────────────────────────

/// Shared spacing scale — Mobi × Rayon system.
abstract final class CoolSpace {
  static const double x0 = 0.0;
  static const double x1 = 4.0; // m1
  static const double x2 = 8.0; // m2
  static const double x3 = 12.0; // m3
  static const double x4 = 16.0; // m4
  static const double x5 = 20.0;
  static const double x6 = 24.0; // m5
  static const double x7 = 32.0; // m6
  static const double x8 = 40.0;
  static const double x9 = 48.0; // m7
  static const double x10 = 64.0;
  static const double x12 = x3;
  static const double x16 = 88.0;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: x4,
    vertical: x4,
  );

  static const EdgeInsets sectionPadding = EdgeInsets.all(x6);
  static const EdgeInsets denseSectionPadding = EdgeInsets.all(x5);
  static const EdgeInsets scaffoldPadding = EdgeInsets.fromLTRB(x4, 0, x4, 96);
}

// ──────────────────────────────────────────────────────────────────────────────
// Radii — tight, precise, fintech
// ──────────────────────────────────────────────────────────────────────────────

/// Corner radius scale — production card and shell geometry.
abstract final class CoolRadii {
  static const double xs = 12.0;
  static const double sm = 16.0;
  static const double md = 22.0;
  static const double lg = 28.0;
  static const double xl = 32.0;
  static const double xxl = 36.0;
  static const double pill = 999.0;
}

// ──────────────────────────────────────────────────────────────────────────────
// Blur
// ──────────────────────────────────────────────────────────────────────────────

/// Blur guidance for glass surfaces and atmospheric backgrounds.
abstract final class CoolBlur {
  static const double subtle = 12.0;
  static const double standard = 24.0; // glass nav bar
  static const double overlay = 32.0; // modals
  static const double heavy = overlay;
  static const double atmospheric = 120.0; // background blobs
}

// ──────────────────────────────────────────────────────────────────────────────
// Elevation
// ──────────────────────────────────────────────────────────────────────────────

abstract final class CoolElevation {
  static const double resting = 0.0;
  static const double raised = 8.0;
  static const double floating = 12.0;
  static const double overlay = 16.0;
}

// ──────────────────────────────────────────────────────────────────────────────
// Tap Targets
// ──────────────────────────────────────────────────────────────────────────────

abstract final class CoolTapTargets {
  static const double minimum = 48.0;
  static const double comfortable = 56.0;
  static const double navigation = 64.0;
}

// ──────────────────────────────────────────────────────────────────────────────
// Motion
// ──────────────────────────────────────────────────────────────────────────────

/// Motion primitives — Mobi × Rayon system.
abstract final class CoolMotion {
  static const Duration press = Duration(milliseconds: 100);
  static const Duration quick = Duration(milliseconds: 200);
  static const Duration standard = Duration(milliseconds: 300);
  static const Duration medium = standard;
  static const Duration emphasized = Duration(milliseconds: 500);

  static const Curve enterCurve = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Curve exitCurve = Cubic(0.4, 0.0, 1.0, 1.0);
  static const Curve pressCurve = Curves.easeInOut;
}

// ──────────────────────────────────────────────────────────────────────────────
// Responsive
// ──────────────────────────────────────────────────────────────────────────────

abstract final class CoolResponsive {
  static double horizontalPaddingForWidth(double width) {
    if (width >= 840) return 40.0;
    if (width >= 600) return 32.0;
    return 16.0; // tighter default (was 24)
  }

  static double maxContentWidthForWidth(double width) {
    if (width >= 840) return 720.0;
    return width;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shadows — simple, no claymorphism
// ──────────────────────────────────────────────────────────────────────────────

/// Shadow recipes — flat, simple.
abstract final class CoolShadows {
  /// Standard card shadow.
  static List<BoxShadow> standard(
    Brightness? brightness, {
    double strength = 1,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.50 * strength),
        blurRadius: 25,
        offset: const Offset(0, 10),
      ),
    ];
  }

  /// Floating element shadow (FABs, nav bar).
  static List<BoxShadow> floating(
    Brightness? brightness, {
    double strength = 1,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.50 * strength),
        blurRadius: 40,
        offset: const Offset(0, 15),
      ),
    ];
  }

  /// Primary CTA glow shadow.
  static List<BoxShadow> primary({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: CoolSemanticColors.dark.accent.withValues(
          alpha: 0.20 * strength,
        ),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Gold accent glow shadow.
  static List<BoxShadow> gold({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: CoolSemanticColors.dark.accentGold.withValues(
          alpha: 0.20 * strength,
        ),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Glass Opacity (simplified — dark-only)
// ──────────────────────────────────────────────────────────────────────────────

/// Per-mode opacity tokens (dark-only now, brightness param kept for compat).
abstract final class CoolGlassOpacity {
  static double glassBackground(Brightness brightness) => 0.05;
  static double glassBorderWhite(Brightness brightness) => 0.10;
  static double glassGradientWhite(Brightness brightness) => 0.05;
}
