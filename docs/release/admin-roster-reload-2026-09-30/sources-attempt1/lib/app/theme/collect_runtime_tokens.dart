import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_radius.dart';

/// Owner-selected photographic editorial-card adapter, 5 Sep 2026.
/// The captured card is approximately 358 x 438 pixels with 24-pixel corners.
/// Text growth, group data and action targets remain Collect-specific.
class CollectGroupCardTokens {
  const CollectGroupCardTokens._();

  static const radius = BorderRadius.all(Radius.circular(24));
  static const aspectRatio = 358 / 438;
  static const gap = 16.0;
  static const padding = EdgeInsets.all(16);
  static const fadeHeight = 96.0;
  static const titleSize = 22.0;
  static const metadataSize = 16.0;
  static const titleLeading = 1.15;
  static const metadataLeading = 1.2;
  static const footerInk = Color(0xFF242726);
}

class CollectRuntimeTokens {
  const CollectRuntimeTokens._();

  // Navigation stays dark in both modes; never reuse this on adaptive page text.
  static Color get navigationForeground => CollectColors.publicWhite;

  // Physical-pixel adapters: DESK-003/004/005/007/001. See the palette
  // measurement record for source hashes, sample positions and limitations.
  static const _backdrops = <CollectBackdropTone, List<Color>>{
    CollectBackdropTone.account: [
      Color(0xFF3656FD),
      Color(0xFF395CFC),
      Color(0xFF1F34EA),
      Color(0xFF0D1DC9),
      Color(0xFF051194),
      Color(0xFF02065B),
      Color(0xFF010443),
      Color(0xFF000546),
      Color(0xFF010339),
      Color(0xFF000234),
    ],
    CollectBackdropTone.groups: [
      Color(0xFF36ADC1),
      Color(0xFF39AFC4),
      Color(0xFF248195),
      Color(0xFF115164),
      Color(0xFF0C3645),
      Color(0xFF092630),
      Color(0xFF011C23),
      Color(0xFF051C23),
      Color(0xFF03181F),
      Color(0xFF02171F),
    ],
    CollectBackdropTone.activity: [
      Color(0xFF6A3CDE),
      Color(0xFF5C3AC1),
      Color(0xFF2A1955),
      Color(0xFF1B123A),
      Color(0xFF17133A),
      Color(0xFF16133A),
      Color(0xFF17133A),
      Color(0xFF17123A),
      Color(0xFF16133A),
      Color(0xFF161539),
    ],
    CollectBackdropTone.profile: [
      Color(0xFF953DF5),
      Color(0xFF983AF6),
      Color(0xFF844AF2),
      Color(0xFF7351F3),
      Color(0xFF6749F2),
      Color(0xFF4D4AD1),
      Color(0xFF332C83),
      Color(0xFF342B7D),
      Color(0xFF302B7D),
      Color(0xFF2D2C7B),
    ],
    CollectBackdropTone.authentication: [
      Color(0xFF435E8E),
      Color(0xFF435E8E),
      Color(0xFF3C518D),
      Color(0xFF2D3E8D),
      Color(0xFF1B2680),
      Color(0xFF141C6E),
      Color(0xFF111861),
      Color(0xFF0F164E),
      Color(0xFF0E113D),
      Color(0xFF0E113D),
    ],
  };

  static Gradient? overviewBackdrop(
    CollectColors colors,
    Brightness brightness,
    CollectBackdropTone tone, {
    required bool highContrast,
    double scrollOffset = 0,
    double viewportHeight = 1,
  }) {
    final palette = _backdrops[tone];
    if (palette == null || highContrast) return null;
    final shift = 2 * scrollOffset / viewportHeight.clamp(1, double.infinity);
    final begin = Alignment(0, -1 - shift);
    final end = Alignment(0, 1 - shift);
    if (brightness == Brightness.light) {
      return LinearGradient(
        begin: begin,
        end: end,
        colors: [
          Color.alphaBlend(
            palette.first.withValues(alpha: 0.12),
            colors.canvas,
          ),
          colors.canvas,
        ],
        stops: const [0, 0.6],
      );
    }
    return LinearGradient(
      begin: begin,
      end: end,
      colors: palette,
      stops: const [
        0,
        0.041,
        0.117,
        0.210,
        0.350,
        0.478,
        0.583,
        0.700,
        0.875,
        1,
      ],
    );
  }

  static Color? overviewSurface(CollectBackdropTone tone) => switch (tone) {
    CollectBackdropTone.account => const Color(0xFF131850),
    CollectBackdropTone.groups => const Color(0xFF172B32),
    CollectBackdropTone.activity => const Color(0xFF282449),
    CollectBackdropTone.profile => const Color(0xFF403A86),
    CollectBackdropTone.authentication || CollectBackdropTone.plain => null,
  };

  static Color chromeForeground(CollectColors colors) => colors.textPrimary;

  static Color chromeMutedForeground(CollectColors colors) {
    return colors.textSecondary;
  }

  static Color chromeControl(CollectColors colors) {
    return colors.textPrimary.computeLuminance() > 0.5
        ? CollectColors.referenceChromeBlack
        : colors.surfaceReadable;
  }

  static Color chromeControlBorder(CollectColors colors) {
    return colors.textPrimary.withValues(alpha: 0.12);
  }

  static Color quickActionFill(CollectColors colors) =>
      colors.textPrimary.withValues(
        alpha: colors.textPrimary.computeLuminance() > 0.5 ? 0.18 : 0.08,
      );

  static Color chromeAvatarBorder(CollectColors colors) {
    return colors.borderSoft;
  }

  static List<BoxShadow> chromeAvatarShadow() => [
    BoxShadow(
      color: CollectColors.publicBlack.withValues(alpha: 0.24),
      blurRadius: 18,
      offset: const Offset(0, 10),
    ),
  ];

  static Color inputFill(CollectColors colors) => colors.surfaceRaised;

  static Color controlBorder(CollectColors colors) => colors.controlBorder;

  static Color inputBorder(CollectColors colors) => controlBorder(colors);

  static Color inputShadow(CollectColors colors) {
    return colors.textPrimary.withValues(alpha: 0.12);
  }

  static Color chipBackground(CollectColors colors) => colors.surfaceRaised;

  static Color chipSelectedBackground(CollectColors colors) {
    return colors.actionColor;
  }

  static Color chipBorder(CollectColors colors, {required bool selected}) {
    return selected ? colors.borderAccent : colors.borderSoft;
  }

  static Color badgeBackground(CollectColors colors, Color accent) {
    return Color.alphaBlend(
      accent.withValues(alpha: 0.10),
      colors.surfaceRaised,
    );
  }

  static Color badgeBorder(CollectColors colors, Color accent) {
    return accent.withValues(alpha: 0.18);
  }

  static Color cardBackground(
    CollectColors colors,
    Brightness brightness,
    CollectRuntimeCardEmphasis emphasis,
    Color? accentColor, {
    CollectBackdropTone tone = CollectBackdropTone.plain,
    bool highContrast = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final overview = isDark && !highContrast ? overviewSurface(tone) : null;
    return switch (emphasis) {
      CollectRuntimeCardEmphasis.flat => overview ?? colors.surface,
      CollectRuntimeCardEmphasis.outline => colors.surfaceRaised,
      CollectRuntimeCardEmphasis.tonal => Color.alphaBlend(
        (accentColor ?? colors.actionColor).withValues(
          alpha: isDark ? 0.14 : 0.07,
        ),
        colors.surfaceRaised,
      ),
      CollectRuntimeCardEmphasis.glow => colors.surfaceRaised,
      CollectRuntimeCardEmphasis.compact => colors.surfaceRaised,
      CollectRuntimeCardEmphasis.hero ||
      CollectRuntimeCardEmphasis.normal => overview ?? colors.surfaceReadable,
    };
  }

  static double cardOpacity(
    Brightness brightness,
    CollectRuntimeCardEmphasis emphasis,
  ) {
    return 1;
  }

  static Border? cardBorder(
    CollectColors colors,
    Brightness brightness,
    CollectRuntimeCardEmphasis emphasis,
    Color? accentColor,
  ) {
    return switch (emphasis) {
      CollectRuntimeCardEmphasis.flat ||
      CollectRuntimeCardEmphasis.glow ||
      CollectRuntimeCardEmphasis.hero ||
      CollectRuntimeCardEmphasis.tonal ||
      CollectRuntimeCardEmphasis.normal => null,
      CollectRuntimeCardEmphasis.outline => Border.all(color: colors.border),
      CollectRuntimeCardEmphasis.compact => Border.all(
        color: colors.border.withValues(alpha: 0.72),
      ),
    };
  }

  static List<BoxShadow> cardShadows(
    CollectColors colors,
    Brightness brightness,
    CollectRuntimeCardEmphasis emphasis,
    Color? accentColor,
  ) {
    return const <BoxShadow>[];
  }

  static BorderRadius cardRadius(CollectRuntimeCardEmphasis emphasis) {
    return switch (emphasis) {
      CollectRuntimeCardEmphasis.hero ||
      CollectRuntimeCardEmphasis.glow => CollectRadius.cardLargeBorder,
      CollectRuntimeCardEmphasis.compact => CollectRadius.mdBorder,
      CollectRuntimeCardEmphasis.flat ||
      CollectRuntimeCardEmphasis.normal ||
      CollectRuntimeCardEmphasis.tonal ||
      CollectRuntimeCardEmphasis.outline => CollectRadius.cardBorder,
    };
  }

  static Color paymentStepLine(CollectColors colors, {required bool active}) {
    return active ? colors.success : colors.border.withValues(alpha: 0.72);
  }
}

enum CollectRuntimeCardEmphasis {
  flat,
  normal,
  hero,
  tonal,
  glow,
  outline,
  compact,
}

enum CollectBackdropTone {
  plain,
  account,
  groups,
  activity,
  profile,
  authentication,
}
