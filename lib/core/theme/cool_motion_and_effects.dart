part of 'cool_foundations.dart';

abstract final class CoolBlur {
  static const double subtle = 12.0;
  static const double standard = 24.0;
  static const double overlay = 32.0;
  static const double heavy = overlay;
  static const double atmospheric = 120.0;
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

abstract final class CoolShadows {
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
        offset: const Offset(0, 1),
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
        offset: const Offset(0, 0),
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
        color: Colors.white.withValues(alpha: 0.06 * strength),
        blurRadius: 1,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.44 * strength),
        blurRadius: 36,
        offset: const Offset(0, 14),
      ),
    ];
  }

  /// Claymorphic outer shadow: deep ambient + topline highlight.
  /// Apply alongside an inner-gradient overlay for the full clay effect.
  static List<BoxShadow> claymorphicCard({
    Color? glowColor,
    double strength = 1,
  }) {
    return <BoxShadow>[
      // Top-edge specular (simulates inner top highlight)
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.14 * strength),
        blurRadius: 1,
        spreadRadius: 0,
        offset: const Offset(0, 1),
      ),
      // Ambient depth
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.38 * strength),
        blurRadius: 24,
        spreadRadius: -2,
        offset: const Offset(0, 12),
      ),
      // Colored glow bloom
      if (glowColor != null)
        BoxShadow(
          color: glowColor.withValues(alpha: 0.20 * strength),
          blurRadius: 40,
          spreadRadius: -4,
          offset: const Offset(0, 20),
        ),
    ];
  }
}

abstract final class CoolGlassOpacity {
  static double glassBackground(Brightness brightness) => 0.05;
  static double glassBorderWhite(Brightness brightness) => 0.10;
  static double glassGradientWhite(Brightness brightness) => 0.05;
}
