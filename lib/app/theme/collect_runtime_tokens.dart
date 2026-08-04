import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_radius.dart';

class CollectRuntimeTokens {
  const CollectRuntimeTokens._();

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

  static Color chromeForeground(CollectColors colors) => colors.onImagePrimary;

  static Color chromeMutedForeground(CollectColors colors) {
    return colors.onImagePrimary.withValues(alpha: 0.97);
  }

  static Color chromeControl(CollectColors colors) {
    return colors.onImagePrimary.withValues(alpha: 0.14);
  }

  static Color chromeControlBorder(CollectColors colors) {
    return CollectColors.transparentColor;
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

  static Color inputFill(CollectColors colors) => colors.surfaceRaised;

  static Color controlBorder(CollectColors colors) => colors.controlBorder;

  static Color inputBorder(CollectColors colors) => controlBorder(colors);

  static Color inputShadow(CollectColors colors) {
    return colors.periwinklePaint.withValues(alpha: 0.18);
  }

  static Color chipBackground(CollectColors colors) => colors.surfaceRaised;

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
