part of 'cool_foundations.dart';

abstract final class CoolBlur {
  static const double subtle = 6.0;
  static const double standard = 12.0;
  static const double overlay = 20.0;
  static const double heavy = overlay;
  static const double glass = 24.0;
  static const double atmospheric = 56.0;
}

abstract final class CoolElevation {
  static const double resting = 0.0;
  static const double raised = 8.0;
  static const double floating = 12.0;
  static const double overlay = 16.0;
}

abstract final class CoolTapTargets {
  static const double minimum = 48.0;
  static const double comfortable = 56.0;
  static const double navigation = 64.0;
}

abstract final class CoolMotion {
  static const Duration press = Duration(milliseconds: 100);
  static const Duration quick = Duration(milliseconds: 200);
  static const Duration standard = Duration(milliseconds: 300);
  static const Duration medium = standard;
  static const Duration emphasized = Duration(milliseconds: 500);

  static const Curve enterCurve = Cubic(0.4, 0.0, 0.2, 1.0);
  static const Curve exitCurve = Cubic(0.4, 0.0, 1.0, 1.0);
  static const Curve pressCurve = Curves.easeInOut;

  /// Whether the user has enabled "reduce motion" in system accessibility.
  static bool isReducedMotion(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  /// Returns [duration] when animations are enabled, or [Duration.zero]
  /// when the user has requested reduced motion.
  static Duration resolve(BuildContext context, Duration duration) {
    return isReducedMotion(context) ? Duration.zero : duration;
  }

  /// Returns [curve] when animations are enabled, or [Curves.linear]
  /// when the user has requested reduced motion.
  static Curve resolveCurve(BuildContext context, Curve curve) {
    return isReducedMotion(context) ? Curves.linear : curve;
  }
}

abstract final class CoolResponsive {
  static double horizontalPaddingForWidth(double width) {
    if (width >= 840) return 40.0;
    if (width >= 600) return 32.0;
    return 16.0;
  }

  static double maxContentWidthForWidth(double width) {
    if (width >= 840) return 720.0;
    return width;
  }
}

/// Shared shadow system for restrained, production-friendly depth.
abstract final class CoolShadows {
  static const _shadowBase = Color(0xFF09111F);

  static List<BoxShadow> standard(
    Brightness? brightness, {
    double strength = 1,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: _shadowBase.withValues(alpha: 0.10 * strength),
        blurRadius: 18,
        spreadRadius: 0,
        offset: const Offset(0, 8),
      ),
    ];
  }

  static List<BoxShadow> floating(
    Brightness? brightness, {
    double strength = 1,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: _shadowBase.withValues(alpha: 0.14 * strength),
        blurRadius: 28,
        spreadRadius: -2,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> primary({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFF3E63FF).withValues(alpha: 0.16 * strength),
        blurRadius: 20,
        spreadRadius: -4,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static List<BoxShadow> gold({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: const Color(0xFFE7B24B).withValues(alpha: 0.18 * strength),
        blurRadius: 18,
        spreadRadius: -4,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static List<BoxShadow> clay({Color? accentColor, double strength = 1}) {
    final accent = accentColor ?? const Color(0xFF3E63FF);
    return <BoxShadow>[
      BoxShadow(
        color: _shadowBase.withValues(alpha: 0.12 * strength),
        blurRadius: 20,
        spreadRadius: -4,
        offset: const Offset(0, 10),
      ),
      BoxShadow(
        color: accent.withValues(alpha: 0.08 * strength),
        blurRadius: 16,
        spreadRadius: -6,
        offset: const Offset(0, 6),
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

  static List<BoxShadow> glass({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: _shadowBase.withValues(alpha: 0.12 * strength),
        blurRadius: 24,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
    ];
  }

  static List<BoxShadow> ambientFloat({double strength = 1}) {
    return <BoxShadow>[
      BoxShadow(
        color: _shadowBase.withValues(alpha: 0.10 * strength),
        blurRadius: 32,
        spreadRadius: -8,
        offset: const Offset(0, 14),
      ),
    ];
  }

  static List<BoxShadow> claymorphicCard({
    Color? glowColor,
    double strength = 1,
  }) {
    return <BoxShadow>[
      BoxShadow(
        color: _shadowBase.withValues(alpha: 0.14 * strength),
        blurRadius: 28,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
      if (glowColor != null)
        BoxShadow(
          color: glowColor.withValues(alpha: 0.06 * strength),
          blurRadius: 18,
          spreadRadius: -6,
          offset: const Offset(0, 6),
        ),
    ];
  }
}

abstract final class CoolGlassOpacity {
  static double glassBackground(Brightness brightness) =>
      brightness == Brightness.dark ? 0.82 : 0.92;
  static double glassBorderWhite(Brightness brightness) => 0.08;
  static double glassGradientWhite(Brightness brightness) => 0.03;
}
