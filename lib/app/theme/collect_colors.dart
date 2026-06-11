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
  Color get onAccent => textPrimary;
  Color get selectedOnAccent => textPrimary;
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

  Color get screenBase => brandPaper;

  Color get glassPanel => surfaceReadable.withValues(alpha: 0.82);

  Color get glassPanelStrong => surfaceReadable.withValues(alpha: 0.90);

  Color get glassControl => surfaceReadable.withValues(alpha: 0.78);

  Color get glassBorder => borderAccent.withValues(alpha: 0.78);

  Color get glassScrim => inkPrimary.withValues(alpha: 0.08);

  LinearGradient get screenGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      _screenTint(brandMintGreen, 0.34),
      _screenTint(brandPeriwinkle, 0.38),
      _screenTint(brandDustyRose, 0.24),
      _screenTint(brandOrangeRed, 0.18),
      brandPaper,
    ],
    stops: const [0, 0.22, 0.5, 0.78, 1],
  );

  Color _screenTint(Color brand, double alpha) {
    return Color.alphaBlend(brand.withValues(alpha: alpha), brandPaper);
  }

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
  CollectColors get collectColors =>
      Theme.of(this).extension<CollectColors>() ?? CollectColors.light;
}
