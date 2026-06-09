import 'package:flutter/material.dart';

class CollectColors extends ThemeExtension<CollectColors> {
  const CollectColors({
    required this.periwinklePaint,
    required this.mintPaint,
    required this.rosePaint,
    required this.orangePaint,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.border,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
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
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color border;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  static const brandPaper = Color(0xFFFAF8F5);
  static const brandPeriwinkle = Color(0xFF8885F0);
  static const brandMintGreen = Color(0xFF3CD070);
  static const brandDustyRose = Color(0xFFD38B96);
  static const brandOrangeRed = Color(0xFFFF5E43);
  static const transparentColor = Color(0x00000000);

  static const brandPaintColors = <Color>[
    brandPeriwinkle,
    brandMintGreen,
    brandDustyRose,
    brandOrangeRed,
  ];
  static const brandPaintHexes = <String>[
    '#8885F0',
    '#3CD070',
    '#D38B96',
    '#FF5E43',
  ];
  static const brandPrimaryColors = <Color>[
    brandPaper,
    brandPeriwinkle,
    brandMintGreen,
    brandDustyRose,
    brandOrangeRed,
    transparentColor,
  ];
  static const brandPrimaryHexes = <String>[
    '#FAF8F5',
    '#8885F0',
    '#3CD070',
    '#D38B96',
    '#FF5E43',
    '#00000000',
  ];

  static const light = CollectColors(
    periwinklePaint: brandPeriwinkle,
    mintPaint: brandMintGreen,
    rosePaint: brandDustyRose,
    orangePaint: brandOrangeRed,
    canvas: brandPaper,
    surface: brandPaper,
    surfaceRaised: brandPaper,
    surfaceMuted: brandDustyRose,
    border: brandPeriwinkle,
    success: brandMintGreen,
    warning: brandOrangeRed,
    danger: brandOrangeRed,
    info: brandPeriwinkle,
    textPrimary: brandPeriwinkle,
    textSecondary: brandDustyRose,
    textMuted: brandMintGreen,
  );

  Color get paper => canvas;
  Color get surfaceLow => surfaceMuted;
  Color get surfaceHigh => surfaceRaised;
  Color get actionColor => orangePaint;
  Color get priorityColor => periwinklePaint;
  Color get outlineSoft => border;
  Color get successInk => success;
  Color get dangerSoft => danger;
  Color get brandPrimary => brandPeriwinkle;
  Color get brandFoundation => brandPaper;
  Color get brandSecondary => brandDustyRose;
  Color get brandAction => brandOrangeRed;
  Color get brandSuccess => brandMintGreen;
  Color get transparent => transparentColor;
  Color get onAccent => brandPaper;
  Color get selectedOnAccent => brandPaper;
  Color get onImagePrimary => brandPaper;
  Color get onImageMuted => brandPaper.withValues(alpha: 0.72);
  Color get exportCanvas => brandPaper;
  Color get exportPaint => brandPeriwinkle;
  Color get shadowPaint => brandPeriwinkle;
  Color get imageScrimSoft => brandPeriwinkle.withValues(alpha: 0.14);
  Color get imageScrimStrong => brandPeriwinkle.withValues(alpha: 0.58);
  Color get cameraScrim => brandPeriwinkle.withValues(alpha: 0.54);
  Color get cameraScrimStrong => brandPeriwinkle.withValues(alpha: 0.68);
  Color get statusGranted => success;
  Color get statusBlocked => danger;

  static const brandPrimaryOptions = <CollectPaletteOption>[
    CollectPaletteOption('#FAF8F5', brandPaper),
    CollectPaletteOption('#8885F0', brandPeriwinkle),
    CollectPaletteOption('#3CD070', brandMintGreen),
    CollectPaletteOption('#D38B96', brandDustyRose),
    CollectPaletteOption('#FF5E43', brandOrangeRed),
    CollectPaletteOption('#00000000', transparentColor),
  ];

  static const brandPaintOptions = <CollectPaletteOption>[
    CollectPaletteOption('#8885F0', brandPeriwinkle),
    CollectPaletteOption('#3CD070', brandMintGreen),
    CollectPaletteOption('#D38B96', brandDustyRose),
    CollectPaletteOption('#FF5E43', brandOrangeRed),
  ];

  Color get screenBase => brandPaper;

  Color get glassPanel => brandPaper.withValues(alpha: 0.82);

  Color get glassPanelStrong => brandPaper.withValues(alpha: 0.88);

  Color get glassControl => brandPaper.withValues(alpha: 0.78);

  Color get glassBorder => brandPeriwinkle.withValues(alpha: 0.42);

  Color get glassScrim => brandPeriwinkle.withValues(alpha: 0.08);

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
    const alpha = 0.10;
    return switch (tone) {
      CollectStatusTone.success => success.withValues(alpha: alpha),
      CollectStatusTone.warning => warning.withValues(alpha: alpha),
      CollectStatusTone.danger => danger.withValues(alpha: alpha),
      CollectStatusTone.info => actionColor.withValues(alpha: alpha),
      CollectStatusTone.privacy => periwinklePaint.withValues(alpha: alpha),
      CollectStatusTone.neutral => surfaceMuted.withValues(alpha: alpha),
    };
  }

  Color statusForeground(CollectStatusTone tone) {
    return switch (tone) {
      CollectStatusTone.success => success,
      CollectStatusTone.warning => warning,
      CollectStatusTone.danger => danger,
      CollectStatusTone.info => info,
      CollectStatusTone.privacy => periwinklePaint,
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
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? border,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
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
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
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
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
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
