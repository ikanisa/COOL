import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

export 'package:google_fonts/google_fonts.dart';

// ──────────────────────────────────────────────────────────────────────────────
// ROUGEBLACK Design System — Foundation Tokens
//
// Shared light/dark foundations for the production UI system.
// Dark remains the primary runtime presentation; light is maintained for
// design-system parity, widget adaptation, and test coverage.
// ──────────────────────────────────────────────────────────────────────────────

/// Production semantic color tokens — ROUGEBLACK system.
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
    // ── PAYLEDGER — Sovereign Architect background system ─────────────
    appBackground: Color(0xFF0D0A27), // deep void
    elevatedBackground: Color(0xFF120F2F), // dark base
    cardSurface: Color(0xFF1E1A41), // raised command surface
    cardSurfaceStrong: Color(0xFF241F50), // elevated navy
    glassSurface: Color(0x0FFFFFFF), // white/6 + backdrop-blur
    overlaySurface: Color(0xFF120F2F), // modals
    // ── Text ─────────────────────────────────────────────────────────
    primaryText: Color(0xFFF7F9FC), // snow white
    secondaryText: Color(0xFF8B8A9E), // muted lavender-grey
    tertiaryText: Color(0xFF5E5C77), // dark muted steel
    // ── Accent — Sovereign Architect shared glow system ──────────────
    accent: Color(0xFF6C63FF), // neon violet
    accentStrong: Color(0xFF8982FF), // intense neon 
    accentForeground: Color(0xFFFFFFFF),
    accentGold: Color(0xFFFACC15), // bright gold (status)
    // ── Borders (No-Line Rule) ──────────────────────────────────────
    divider: Color(0x08FFFFFF), // ultra-subtle highlight
    border: Color(0x0AFFFFFF), // white/4 specular
    borderStrong: Color(0x14FFFFFF), // white/8 glow
    // ── Status ───────────────────────────────────────────────────────
    success: Color(0xFF10B981), // pure emerald
    warning: Color(0xFFF59E0B), // vivid amber
    danger: Color(0xFFEF4444), // stark crimson
    info: Color(0xFF3B82F6), // crisp azure
    neutral: Color(0xFF8B8A9E), // lavender-grey
    // ── Chips & buttons ─────────────────────────────────────────────
    chipBackground: Color(0xFF1E1A41), // raised command surface 
    chipSelectedBackground: Color(0xFF6C63FF),
    buttonPrimaryBackground: Color(0xFF6C63FF),
    buttonSecondaryBackground: Color(0x14FFFFFF), // white/8
    inputSurface: Color(0x0AFFFFFF), // white/4
    // ── Shadow & highlight ──────────────────────────────────────────
    shadowColor: Color(0xFF050314), // ink void
    highlightColor: Color(0x14FFFFFF), // subtle specular rim
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

/// Typography helpers anchored to [TextTheme] with Space Mono, Syne, and DM Sans 
/// for values and headings.
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

  /// Monospace text — Space Mono for values, IDs, labels.
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
    return GoogleFonts.spaceMono(
      textStyle: resolvedBase.copyWith(
        color: color ?? resolvedBase.color ?? _defaultColor,
        fontWeight: fontWeight ?? resolvedBase.fontWeight,
        letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
        height: height ?? resolvedBase.height,
      ),
    );
  }

  /// mobi-label: 10px, Space Mono, uppercase, wide tracking.
  TextStyle mobiLabel({Color? color}) {
    final labelColor = _textTheme.labelSmall?.color ?? _defaultColor;
    return GoogleFonts.spaceMono(
      textStyle: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color ?? labelColor,
        letterSpacing: 1.0,
        height: 1.2,
      ),
    );
  }

  /// mobi-value: 14px, Space Mono, standard tracking.
  TextStyle mobiValue({Color? color}) {
    return GoogleFonts.spaceMono(
      textStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color ?? _defaultColor,
        letterSpacing: 0.0,
        height: 1.3,
      ),
    );
  }

  /// Large hero number for financial dashboards (MoMo balance, group totals).
  ///
  /// Syne 48px, Black 900, tight height for stamp-like impact.
  TextStyle heroNumber({Color? color}) {
    return GoogleFonts.syne(
      textStyle: TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w900,
        color: color ?? _defaultColor,
        letterSpacing: -1.5,
        height: 0.9,
      ),
    );
  }

  /// DM Sans text for standard UI bindings.
  TextStyle display(
    TextStyle? base, {
    Color? color,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
  }) {
    final resolvedBase =
        base ??
        _textTheme.bodyLarge ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    return GoogleFonts.dmSans(
      textStyle: resolvedBase.copyWith(
        color: color ?? resolvedBase.color ?? _defaultColor,
        fontWeight: fontWeight ?? resolvedBase.fontWeight ?? FontWeight.w600,
        letterSpacing: letterSpacing ?? resolvedBase.letterSpacing,
        height: height ?? resolvedBase.height,
      ),
    );
  }

  /// Syne for uppercase bold headers.
  TextStyle displayCondensed(
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
    return GoogleFonts.syne(
      textStyle: resolvedBase.copyWith(
        color: color ?? resolvedBase.color ?? _defaultColor,
        fontWeight: fontWeight ?? resolvedBase.fontWeight ?? FontWeight.w900,
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

/// Shared spacing scale — ROUGEBLACK system.
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

/// Motion primitives — ROUGEBLACK system.
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
// No-Line Rule Shadows (Specular Highlights)
// ──────────────────────────────────────────────────────────────────────────────

/// Shadow recipes — PAYLEDGER system.
abstract final class CoolShadows {
  /// Specular highlight standard (no strong drop shadows, mainly inner borders/specular).
  static List<BoxShadow> standard(
    Brightness? brightness, {
    double strength = 1,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.05 * strength),
        blurRadius: 1,
        spreadRadius: 0,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.20 * strength),
        blurRadius: 20,
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
        color: Colors.white.withValues(alpha: 0.08 * strength),
        blurRadius: 1,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.30 * strength),
        blurRadius: 40,
        offset: const Offset(0, 15),
      ),
    ];
  }

  /// Primary specular glow.
  static List<BoxShadow> primary({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFF6C63FF).withValues(alpha: 0.25 * strength),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.15 * strength),
        blurRadius: 1,
        offset: const Offset(0, 1), // Top specular rim
      ),
    ];
  }

  static List<BoxShadow> gold({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFFFACC15).withValues(alpha: 0.25 * strength),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Removes outdated claymorphic, aliases to deep specular.
  static List<BoxShadow> clay({Color? accentColor, double strength = 1}) {
    final accent = accentColor ?? const Color(0xFF6C63FF);
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.40 * strength),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.10 * strength),
        blurRadius: 1,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: accent.withValues(alpha: 0.15 * strength),
        blurRadius: 30,
        offset: const Offset(0, 0), // Ambient glow
      ),
    ];
  }

  static List<BoxShadow> redGlow({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFFEF4444).withValues(alpha: 0.25 * strength),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// Frosted glass overlay shadow.
  static List<BoxShadow> glass({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.05 * strength),
        blurRadius: 1,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.40 * strength),
        blurRadius: 32,
        offset: const Offset(0, 12),
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
