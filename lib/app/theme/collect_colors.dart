import 'package:flutter/material.dart';

class CollectColors extends ThemeExtension<CollectColors> {
  const CollectColors({
    required this.periwinklePaint,
    required this.mintPaint,
    required this.rosePaint,
    required this.orangePaint,
    required this.canvas,
    required this.surface,
    required this.surfaceReadable,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.border,
    required this.borderSoft,
    required this.borderAccent,
    required this.focusRing,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.successForeground,
    required this.infoForeground,
    required this.warningForeground,
    required this.dangerForeground,
    required this.successContainer,
    required this.infoContainer,
    required this.warningContainer,
    required this.dangerContainer,
    required this.neutralContainer,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final Color periwinklePaint;
  final Color mintPaint;
  final Color rosePaint;
  final Color orangePaint;
  final Color canvas;
  final Color surface;
  final Color surfaceReadable;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color border;
  final Color borderSoft;
  final Color borderAccent;
  final Color focusRing;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color successForeground;
  final Color infoForeground;
  final Color warningForeground;
  final Color dangerForeground;
  final Color successContainer;
  final Color infoContainer;
  final Color warningContainer;
  final Color dangerContainer;
  final Color neutralContainer;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  static const brandPaper = Color(0xFFFAF8F5);
  static const brandPeriwinkle = Color(0xFF8885F0);
  static const brandMintGreen = Color(0xFF3CD070);
  static const brandDustyRose = Color(0xFFD38B96);
  static const brandOrangeRed = Color(0xFFFF5E43);
  static const inkPrimary = Color(0xFF252044);
  static const referenceChromeBlack = Color(0xFF050510);
  static const inkSecondary = Color(0xFF4B4664);
  static const inkMuted = Color(0xFF5F5A76);
  static const transparentColor = Color(0x00000000);
  static const secondarySurfaceReadable = Color(0xFFFFFDFB);
  static const secondarySurfaceMuted = Color(0xFFF1ECF7);
  static const secondaryBorderSoft = Color(0xFFDED8EA);
  static const secondaryBorderAccent = Color(0xFFCDC7F5);
  static const secondaryFocusRing = Color(0xFF6F67E8);
  static const semanticSuccessForeground = Color(0xFF137A3F);
  static const semanticInfoForeground = Color(0xFF514DD2);
  static const semanticWarningForeground = Color(0xFFB9472E);
  static const semanticDangerForeground = Color(0xFFB3261E);
  static const semanticSuccessContainer = Color(0xFFE7F8ED);
  static const semanticInfoContainer = Color(0xFFECEBFF);
  static const semanticWarningContainer = Color(0xFFFFE9E3);
  static const semanticDangerContainer = Color(0xFFFFE5DF);
  static const semanticNeutralContainer = Color(0xFFF1ECF7);
  static const referenceAccountNavy = Color(0xFF000840);
  static const referenceAccountNavyDeep = Color(0xFF000838);
  static const referenceAccountBlue = Color(0xFF0818A0);
  static const referenceAccountBlueMid = Color(0xFF0F198E);
  static const referenceAccountBlueDeep = Color(0xFF070D60);
  static const referencePaymentsPurple = Color(0xFF181038);
  static const referencePaymentsPurpleMid = Color(0xFF302848);
  static const referencePaymentsPurpleDeep = Color(0xFF100820);
  static const referenceAssetNavy = Color(0xFF101830);
  static const referenceAssetNavyMid = Color(0xFF303870);
  static const referenceAssetNavySoft = Color(0xFF202858);
  static const referenceRewardsViolet = Color(0xFF302878);
  static const referenceRewardsVioletBright = Color(0xFF7050E8);
  static const referenceRewardsVioletHot = Color(0xFF9838F0);
  static const referenceWealthTeal = Color(0xFF102028);
  static const referenceWealthTealMid = Color(0xFF204050);
  static const referenceWealthTealSoft = Color(0xFF183848);
  static const referenceContentDark = Color(0xFF101018);
  static const referenceContentBronze = Color(0xFF303020);
  static const referenceInvestTeal = Color(0xFF202828);
  static const referenceStockTealBlack = Color(0xFF001010);
  static const publicWhite = Color(0xFFFFFFFF);
  static const publicBlack = Color(0xFF000000);
  static const publicMutedGrey = Color(0xFF84848C);
  static const publicMintSurface = Color(0xFFF3FBF8);
  static const publicHeroPurple = Color(0xFF151029);
  static const publicInkPurple = Color(0xFF171032);
  static const publicDarkInk = Color(0xFF111018);
  static const publicDeepInk = Color(0xFF090912);
  static const publicPanelInk = Color(0xFF131520);
  static const publicSuccessAccent = Color(0xFF65C77B);
  static const publicSoftDanger = Color(0xFFFFF4F4);
  static const publicSoftInfo = Color(0xFFF0F2FF);
  static const publicSoftNeutral = Color(0xFFF6F7FA);
  static const publicSoftLavender = Color(0xFFF7F7FF);
  static const publicLavenderBorder = Color(0xFFE8E3F2);

  static const brandPrimaryColors = <Color>[
    brandPeriwinkle,
    brandMintGreen,
    brandDustyRose,
    brandOrangeRed,
  ];
  static const brandPrimaryHexes = <String>[
    '#8885F0',
    '#3CD070',
    '#D38B96',
    '#FF5E43',
  ];

  static const light = CollectColors(
    periwinklePaint: brandPeriwinkle,
    mintPaint: brandMintGreen,
    rosePaint: brandDustyRose,
    orangePaint: brandOrangeRed,
    canvas: brandPaper,
    surface: brandPaper,
    surfaceReadable: secondarySurfaceReadable,
    surfaceRaised: secondarySurfaceReadable,
    surfaceMuted: secondarySurfaceMuted,
    border: secondaryBorderSoft,
    borderSoft: secondaryBorderSoft,
    borderAccent: secondaryBorderAccent,
    focusRing: secondaryFocusRing,
    success: semanticSuccessForeground,
    warning: semanticWarningForeground,
    danger: semanticDangerForeground,
    info: semanticInfoForeground,
    successForeground: semanticSuccessForeground,
    infoForeground: semanticInfoForeground,
    warningForeground: semanticWarningForeground,
    dangerForeground: semanticDangerForeground,
    successContainer: semanticSuccessContainer,
    infoContainer: semanticInfoContainer,
    warningContainer: semanticWarningContainer,
    dangerContainer: semanticDangerContainer,
    neutralContainer: semanticNeutralContainer,
    textPrimary: inkPrimary,
    textSecondary: inkSecondary,
    textMuted: inkMuted,
  );

  static const dark = CollectColors(
    periwinklePaint: brandPeriwinkle,
    mintPaint: brandMintGreen,
    rosePaint: brandDustyRose,
    orangePaint: brandOrangeRed,
    canvas: Color(0xFF080810),
    surface: Color(0xFF080810),
    surfaceReadable: Color(0xFF171624),
    surfaceRaised: Color(0xFF201E32),
    surfaceMuted: Color(0xFF2A2740),
    border: Color(0xFF3E3A58),
    borderSoft: Color(0xFF474263),
    borderAccent: Color(0xFF6962AA),
    focusRing: Color(0xFFA7A2FF),
    success: Color(0xFF73E39B),
    warning: Color(0xFFFFA487),
    danger: Color(0xFFFF8C78),
    info: Color(0xFFB8B4FF),
    successForeground: Color(0xFF73E39B),
    infoForeground: Color(0xFFB8B4FF),
    warningForeground: Color(0xFFFFA487),
    dangerForeground: Color(0xFFFF8C78),
    successContainer: Color(0xFF123822),
    infoContainer: Color(0xFF28234E),
    warningContainer: Color(0xFF472117),
    dangerContainer: Color(0xFF4B1D17),
    neutralContainer: Color(0xFF2A2740),
    textPrimary: Color(0xFFF7F4FF),
    textSecondary: Color(0xFFD0CBDC),
    textMuted: Color(0xFFAAA3BA),
  );

  Color get paper => canvas;
  Color get surfaceLow => surfaceMuted;
  Color get surfaceHigh => surfaceRaised;
  Color get actionColor => orangePaint;
  Color get priorityColor => periwinklePaint;
  Color get outlineSoft => borderSoft;
  Color get successInk => successForeground;
  Color get dangerSoft => dangerForeground;
  Color get brandPrimary => brandPeriwinkle;
  Color get brandFoundation => brandPaper;
  Color get brandSecondary => brandDustyRose;
  Color get brandAction => brandOrangeRed;
  Color get brandSuccess => brandMintGreen;
  Color get transparent => transparentColor;
  Color get onAccent => inkPrimary;
  Color get selectedOnAccent => inkPrimary;
  Color get onImagePrimary => brandPaper;
  Color get onImageMuted => brandPaper.withValues(alpha: 0.72);
  Color get exportCanvas => brandPaper;
  Color get exportPaint => brandPeriwinkle;
  Color get shadowPaint => brandPeriwinkle;
  Color get imageScrimSoft => brandPeriwinkle.withValues(alpha: 0.14);
  Color get imageScrimStrong => brandPeriwinkle.withValues(alpha: 0.58);
  Color get cameraScrim => brandPeriwinkle.withValues(alpha: 0.54);
  Color get cameraScrimStrong => brandPeriwinkle.withValues(alpha: 0.68);
  Color get statusGranted => successForeground;
  Color get statusBlocked => dangerForeground;

  static const brandPrimaryOptions = <CollectPaletteOption>[
    CollectPaletteOption('#8885F0', brandPeriwinkle),
    CollectPaletteOption('#3CD070', brandMintGreen),
    CollectPaletteOption('#D38B96', brandDustyRose),
    CollectPaletteOption('#FF5E43', brandOrangeRed),
  ];

  Color get screenBase => referencePaymentsPurple;

  Color get glassPanel => surfaceReadable.withValues(alpha: 0.82);

  Color get glassPanelStrong => surfaceReadable.withValues(alpha: 0.90);

  Color get glassControl => surfaceReadable.withValues(alpha: 0.78);

  Color get glassBorder => borderAccent.withValues(alpha: 0.78);

  Color get glassScrim => inkPrimary.withValues(alpha: 0.08);

  LinearGradient get screenGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referencePaymentsPurpleMid,
      referencePaymentsPurple,
      referencePaymentsPurpleDeep,
    ],
    stops: [0, 0.52, 1],
  );

  Gradient screenGradientForPath(String? path) {
    final route = path ?? '';
    if (route == '/home' ||
        route.startsWith('/onboarding') ||
        route.startsWith('/auth')) {
      return referenceAccountGradient;
    }
    if (route.startsWith('/groups/create') ||
        route.startsWith('/settings/profile') ||
        route.startsWith('/settings/readiness') ||
        route.startsWith('/permissions/sms') ||
        route.startsWith('/permissions/camera') ||
        route.startsWith('/permissions/device') ||
        route.startsWith('/permissions/notifications-denied') ||
        route.startsWith('/platform/iphone-create-unavailable')) {
      return referenceWealthGradient;
    }
    if (route.contains('/pay/') ||
        route.contains('/contribute') ||
        route.contains('/support/payment') ||
        route.contains('/state/') ||
        route.contains('/ledger')) {
      return referenceAssetGradient;
    }
    if (route.startsWith('/settings/account') ||
        route.startsWith('/settings/privacy') ||
        route.startsWith('/settings/help') ||
        route.startsWith('/settings/legal')) {
      return referenceContentGradient;
    }
    if (route.startsWith('/share') ||
        route.contains('/share') ||
        route.contains('/invite') ||
        route == '/settings') {
      return referenceRewardsGradient;
    }
    if (route == '/offline' || route == '/sync') return referenceInvestGradient;
    if (route.startsWith('/notifications')) return referenceMarketGradient;
    if (route.startsWith('/groups') || route.startsWith('/c/')) {
      return referencePaymentsGradient;
    }
    return screenGradient;
  }

  static const Gradient referenceAccountGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referenceAccountBlue,
      referenceAccountBlueMid,
      referenceAccountNavyDeep,
      Color(0xFF000030),
    ],
    stops: [0, 0.30, 0.68, 1],
  );

  static const Gradient referenceWealthGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referenceWealthTealMid,
      referenceWealthTealSoft,
      referenceWealthTeal,
      Color(0xFF081820),
    ],
    stops: [0, 0.36, 0.72, 1],
  );

  static const Gradient referencePaymentsGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referencePaymentsPurpleMid,
      referencePaymentsPurple,
      referencePaymentsPurpleDeep,
    ],
    stops: [0, 0.54, 1],
  );

  static const Gradient referenceAssetGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referenceAssetNavyMid,
      referenceAssetNavySoft,
      referenceAssetNavy,
      Color(0xFF000818),
    ],
    stops: [0, 0.34, 0.72, 1],
  );

  static const Gradient referenceRewardsGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referenceRewardsVioletHot,
      referenceRewardsVioletBright,
      referenceRewardsViolet,
      referencePaymentsPurpleDeep,
    ],
    stops: [0, 0.32, 0.70, 1],
  );

  static const Gradient referenceMarketGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referencePaymentsPurpleMid,
      referencePaymentsPurple,
      referenceContentDark,
    ],
    stops: [0, 0.58, 1],
  );

  static const Gradient referenceContentGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referenceContentBronze,
      referencePaymentsPurple,
      referenceContentDark,
    ],
    stops: [0, 0.48, 1],
  );

  static const Gradient referenceInvestGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [referenceInvestTeal, referenceWealthTeal, referenceStockTealBlack],
    stops: [0, 0.48, 1],
  );

  LinearGradient get adminScreenGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      referenceStockTealBlack,
      referenceAssetNavy,
      referencePaymentsPurple,
    ],
    stops: [0, 0.54, 1],
  );

  LinearGradient get glassPanelGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(brandPeriwinkle.withValues(alpha: 0.08), glassPanel),
      Color.alphaBlend(brandDustyRose.withValues(alpha: 0.05), glassPanel),
      glassPanel,
    ],
  );

  Color statusBackground(CollectStatusTone tone) {
    return switch (tone) {
      CollectStatusTone.success => successContainer,
      CollectStatusTone.warning => warningContainer,
      CollectStatusTone.danger => dangerContainer,
      CollectStatusTone.info => infoContainer,
      CollectStatusTone.privacy => infoContainer,
      CollectStatusTone.neutral => neutralContainer,
    };
  }

  Color statusForeground(CollectStatusTone tone) {
    return switch (tone) {
      CollectStatusTone.success => successForeground,
      CollectStatusTone.warning => warningForeground,
      CollectStatusTone.danger => dangerForeground,
      CollectStatusTone.info => infoForeground,
      CollectStatusTone.privacy => infoForeground,
      CollectStatusTone.neutral => textSecondary,
    };
  }

  @override
  CollectColors copyWith({
    Color? periwinklePaint,
    Color? mintPaint,
    Color? rosePaint,
    Color? orangePaint,
    Color? canvas,
    Color? surface,
    Color? surfaceReadable,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? border,
    Color? borderSoft,
    Color? borderAccent,
    Color? focusRing,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? successForeground,
    Color? infoForeground,
    Color? warningForeground,
    Color? dangerForeground,
    Color? successContainer,
    Color? infoContainer,
    Color? warningContainer,
    Color? dangerContainer,
    Color? neutralContainer,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) {
    return CollectColors(
      periwinklePaint: periwinklePaint ?? this.periwinklePaint,
      mintPaint: mintPaint ?? this.mintPaint,
      rosePaint: rosePaint ?? this.rosePaint,
      orangePaint: orangePaint ?? this.orangePaint,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceReadable: surfaceReadable ?? this.surfaceReadable,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      borderAccent: borderAccent ?? this.borderAccent,
      focusRing: focusRing ?? this.focusRing,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      successForeground: successForeground ?? this.successForeground,
      infoForeground: infoForeground ?? this.infoForeground,
      warningForeground: warningForeground ?? this.warningForeground,
      dangerForeground: dangerForeground ?? this.dangerForeground,
      successContainer: successContainer ?? this.successContainer,
      infoContainer: infoContainer ?? this.infoContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
    );
  }

  @override
  CollectColors lerp(ThemeExtension<CollectColors>? other, double t) {
    if (other is! CollectColors) return this;
    return CollectColors(
      periwinklePaint: Color.lerp(periwinklePaint, other.periwinklePaint, t)!,
      mintPaint: Color.lerp(mintPaint, other.mintPaint, t)!,
      rosePaint: Color.lerp(rosePaint, other.rosePaint, t)!,
      orangePaint: Color.lerp(orangePaint, other.orangePaint, t)!,
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceReadable: Color.lerp(surfaceReadable, other.surfaceReadable, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      borderAccent: Color.lerp(borderAccent, other.borderAccent, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      successForeground: Color.lerp(
        successForeground,
        other.successForeground,
        t,
      )!,
      infoForeground: Color.lerp(infoForeground, other.infoForeground, t)!,
      warningForeground: Color.lerp(
        warningForeground,
        other.warningForeground,
        t,
      )!,
      dangerForeground: Color.lerp(
        dangerForeground,
        other.dangerForeground,
        t,
      )!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      neutralContainer: Color.lerp(
        neutralContainer,
        other.neutralContainer,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
    );
  }
}

enum CollectStatusTone { neutral, success, warning, danger, info, privacy }

class CollectPaletteOption {
  const CollectPaletteOption(this.hex, this.color);

  final String hex;
  final Color color;
}

extension CollectColorsTheme on BuildContext {
  CollectColors get collectColors {
    final theme = Theme.of(this);
    return theme.extension<CollectColors>() ??
        (theme.brightness == Brightness.dark
            ? CollectColors.dark
            : CollectColors.light);
  }
}
