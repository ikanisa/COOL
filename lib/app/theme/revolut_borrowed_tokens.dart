import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_radius.dart';
import 'collect_shadows.dart';

class RevolutBorrowedTokens {
  const RevolutBorrowedTokens._();

  static const secondaryColorRoles = <String, Color>{
    'inkPrimary': CollectColors.inkPrimary,
    'inkSecondary': CollectColors.inkSecondary,
    'inkMuted': CollectColors.inkMuted,
    'surfaceReadable': CollectColors.secondarySurfaceReadable,
    'surfaceMuted': CollectColors.secondarySurfaceMuted,
    'borderSoft': CollectColors.secondaryBorderSoft,
    'borderAccent': CollectColors.secondaryBorderAccent,
    'focusRing': CollectColors.secondaryFocusRing,
    'successForeground': CollectColors.semanticSuccessForeground,
    'infoForeground': CollectColors.semanticInfoForeground,
    'warningForeground': CollectColors.semanticWarningForeground,
    'dangerForeground': CollectColors.semanticDangerForeground,
    'successContainer': CollectColors.semanticSuccessContainer,
    'infoContainer': CollectColors.semanticInfoContainer,
    'warningContainer': CollectColors.semanticWarningContainer,
    'dangerContainer': CollectColors.semanticDangerContainer,
    'neutralContainer': CollectColors.semanticNeutralContainer,
  };

  static const secondaryColorHexes = <String>[
    '#252044',
    '#4B4664',
    '#5F5A76',
    '#FFFDFB',
    '#F1ECF7',
    '#DED8EA',
    '#CDC7F5',
    '#6F67E8',
    '#137A3F',
    '#514DD2',
    '#B9472E',
    '#B3261E',
    '#E7F8ED',
    '#ECEBFF',
    '#FFE9E3',
    '#FFE5DF',
    '#F1ECF7',
  ];

  static Color chromeForeground(CollectColors colors) => colors.onImagePrimary;

  static Color chromeMutedForeground(CollectColors colors) {
    return colors.onImagePrimary.withValues(alpha: 0.76);
  }

  static Color chromeControl(CollectColors colors) {
    return CollectColors.referenceChromeBlack.withValues(alpha: 0.92);
  }

  static Color chromeControlBorder(CollectColors colors) {
    return colors.onImagePrimary.withValues(alpha: 0.24);
  }

  static Color chromeAvatarBorder(CollectColors colors) {
    return colors.onImagePrimary.withValues(alpha: 0.22);
  }

  static LinearGradient chromeAvatarGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        CollectColors.referencePaymentsPurple.withValues(alpha: 0.96),
        CollectColors.inkPrimary.withValues(alpha: 0.96),
      ],
    );
  }

  static List<BoxShadow> chromeAvatarShadow() => [
    BoxShadow(
      color: CollectColors.inkPrimary.withValues(alpha: 0.24),
      blurRadius: 18,
      offset: const Offset(0, 10),
    ),
  ];

  static Color inputFill(CollectColors colors) => colors.glassControl;

  static Color inputBorder(CollectColors colors) => colors.glassBorder;

  static Color inputShadow(CollectColors colors) {
    return colors.periwinklePaint.withValues(alpha: 0.18);
  }

  static Color chipBackground(CollectColors colors) => colors.glassControl;

  static Color chipSelectedBackground(CollectColors colors) {
    return colors.periwinklePaint;
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
    CollectBorrowedCardEmphasis emphasis,
    Color? accentColor,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (emphasis) {
      CollectBorrowedCardEmphasis.flat =>
        isDark ? CollectColors.referenceContentDark : colors.surface,
      CollectBorrowedCardEmphasis.outline =>
        isDark
            ? CollectColors.referencePaymentsPurpleDeep
            : colors.surfaceRaised,
      CollectBorrowedCardEmphasis.tonal => Color.alphaBlend(
        (accentColor ?? colors.actionColor).withValues(
          alpha: isDark ? 0.18 : 0.08,
        ),
        isDark ? CollectColors.referenceAssetNavy : colors.surfaceRaised,
      ),
      CollectBorrowedCardEmphasis.glow =>
        isDark ? CollectColors.referenceAssetNavy : colors.surfaceRaised,
      CollectBorrowedCardEmphasis.compact =>
        isDark
            ? CollectColors.referencePaymentsPurpleDeep
            : colors.surfaceRaised,
      CollectBorrowedCardEmphasis.hero || CollectBorrowedCardEmphasis.normal =>
        isDark ? CollectColors.referencePaymentsPurple : colors.surfaceMuted,
    };
  }

  static double cardOpacity(
    Brightness brightness,
    CollectBorrowedCardEmphasis emphasis,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (emphasis) {
      CollectBorrowedCardEmphasis.hero => isDark ? 0.90 : 0.82,
      CollectBorrowedCardEmphasis.glow => isDark ? 0.88 : 0.80,
      CollectBorrowedCardEmphasis.tonal => isDark ? 0.86 : 0.78,
      CollectBorrowedCardEmphasis.compact => isDark ? 0.84 : 0.76,
      CollectBorrowedCardEmphasis.flat => isDark ? 0.82 : 0.70,
      CollectBorrowedCardEmphasis.outline => isDark ? 0.82 : 0.74,
      CollectBorrowedCardEmphasis.normal => isDark ? 0.84 : 0.78,
    };
  }

  static Border? cardBorder(
    CollectColors colors,
    Brightness brightness,
    CollectBorrowedCardEmphasis emphasis,
    Color? accentColor,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (emphasis) {
      CollectBorrowedCardEmphasis.flat => null,
      CollectBorrowedCardEmphasis.glow => Border.all(
        color: (accentColor ?? colors.actionColor).withValues(
          alpha: isDark ? 0.34 : 0.24,
        ),
      ),
      CollectBorrowedCardEmphasis.outline => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.14)
            : colors.border,
      ),
      CollectBorrowedCardEmphasis.compact => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.12)
            : colors.border.withValues(alpha: 0.72),
      ),
      CollectBorrowedCardEmphasis.hero ||
      CollectBorrowedCardEmphasis.tonal ||
      CollectBorrowedCardEmphasis.normal => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.12)
            : colors.border,
      ),
    };
  }

  static List<BoxShadow> cardShadows(
    CollectColors colors,
    Brightness brightness,
    CollectBorrowedCardEmphasis emphasis,
    Color? accentColor,
  ) {
    final isDark = brightness == Brightness.dark;
    return switch (emphasis) {
      CollectBorrowedCardEmphasis.flat ||
      CollectBorrowedCardEmphasis.outline ||
      CollectBorrowedCardEmphasis.compact => const <BoxShadow>[],
      CollectBorrowedCardEmphasis.glow => [
        BoxShadow(
          color: (accentColor ?? colors.actionColor).withValues(
            alpha: isDark ? 0.20 : 0.13,
          ),
          blurRadius: isDark ? 34 : 28,
          offset: const Offset(0, 18),
        ),
      ],
      CollectBorrowedCardEmphasis.hero ||
      CollectBorrowedCardEmphasis.tonal ||
      CollectBorrowedCardEmphasis.normal => CollectShadows.card(),
    };
  }

  static BorderRadius cardRadius(CollectBorrowedCardEmphasis emphasis) {
    return switch (emphasis) {
      CollectBorrowedCardEmphasis.hero ||
      CollectBorrowedCardEmphasis.glow => CollectRadius.cardLargeBorder,
      CollectBorrowedCardEmphasis.compact => CollectRadius.mdBorder,
      CollectBorrowedCardEmphasis.flat ||
      CollectBorrowedCardEmphasis.normal ||
      CollectBorrowedCardEmphasis.tonal ||
      CollectBorrowedCardEmphasis.outline => CollectRadius.cardBorder,
    };
  }

  static Color paymentStepLine(CollectColors colors, {required bool active}) {
    return active ? colors.success : colors.border.withValues(alpha: 0.72);
  }
}

enum CollectBorrowedCardEmphasis {
  flat,
  normal,
  hero,
  tonal,
  glow,
  outline,
  compact,
}
