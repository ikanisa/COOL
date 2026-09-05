import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_radius.dart';

class CollectRuntimeTokens {
  const CollectRuntimeTokens._();

  // Navigation stays dark in both modes; never reuse this on adaptive page text.
  static Color get navigationForeground => CollectColors.brandPaper;

  static Gradient? overviewBackdrop(
    CollectColors colors,
    Brightness brightness,
    CollectBackdropTone tone, {
    required bool highContrast,
  }) {
    if (tone == CollectBackdropTone.plain || highContrast) return null;
    final account = tone == CollectBackdropTone.account;
    if (brightness == Brightness.light) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.alphaBlend(
            (account
                    ? CollectColors.referenceAccountHighlight
                    : CollectColors.referenceDiscoveryViolet)
                .withValues(alpha: 0.12),
            colors.canvas,
          ),
          colors.canvas,
        ],
        stops: const [0, 0.6],
      );
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: account
          ? const [
              CollectColors.referenceAccountHighlight,
              CollectColors.referenceAccountBlue,
              CollectColors.referenceAccountNavy,
              CollectColors.referenceChromeBlack,
            ]
          : const [
              CollectColors.referenceDiscoveryViolet,
              CollectColors.referencePaymentsPurple,
              CollectColors.referencePaymentsPurple,
              CollectColors.referenceChromeBlack,
            ],
      stops: const [0, 0.22, 0.65, 1],
    );
  }

  static Color chromeForeground(CollectColors colors) => colors.textPrimary;

  static Color chromeMutedForeground(CollectColors colors) {
    return colors.textSecondary;
  }

  static Color chromeControl(CollectColors colors) {
    return colors.surfaceRaised;
  }

  static Color chromeControlBorder(CollectColors colors) {
    return colors.borderSoft;
  }

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
    Color? accentColor,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (emphasis) {
      CollectRuntimeCardEmphasis.flat => colors.surface,
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
      CollectRuntimeCardEmphasis.normal => colors.surfaceRaised,
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

enum CollectBackdropTone { plain, account, discovery }
