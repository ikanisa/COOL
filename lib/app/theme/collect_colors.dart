import 'package:flutter/material.dart';

class CollectColors extends ThemeExtension<CollectColors> {
  const CollectColors({
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
  static const semanticSuccessForeground = Color(0xFF137A3F);
  static const semanticInfoForeground = Color(0xFF303035);
  static const semanticWarningForeground = Color(0xFFB9472E);
  static const semanticDangerForeground = Color(0xFFB3261E);
  static const semanticSuccessContainer = Color(0xFFE7F8ED);
  static const semanticInfoContainer = Color(0xFFE8E8EB);
  static const semanticWarningContainer = Color(0xFFFFE9E3);
  static const semanticDangerContainer = Color(0xFFFFE5DF);
  static const referencePaymentsPurple = Color(0xFF181038);
  static const referenceAssetNavy = Color(0xFF101830);
  static const referenceContentDark = Color(0xFF101018);
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
  static const light = CollectColors(
    canvas: Color(0xFFF7F7F8),
    surface: Color(0xFFF7F7F8),
    surfaceReadable: publicWhite,
    surfaceRaised: Color(0xFFF0F0F2),
    surfaceMuted: Color(0xFFE8E8EB),
    border: Color(0xFFDADADD),
    borderSoft: Color(0xFFE1E1E4),
    borderAccent: Color(0xFFB8B8BE),
    focusRing: publicBlack,
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
    neutralContainer: Color(0xFFE8E8EB),
    textPrimary: publicBlack,
    textSecondary: Color(0xFF45454A),
    textMuted: Color(0xFF626269),
  );

  static const dark = CollectColors(
    canvas: Color(0xFF08080A),
    surface: Color(0xFF08080A),
    surfaceReadable: Color(0xFF17171A),
    surfaceRaised: Color(0xFF202024),
    surfaceMuted: Color(0xFF2A2A2F),
    border: Color(0xFF343438),
    borderSoft: Color(0xFF424247),
    borderAccent: Color(0xFF5A5A62),
    focusRing: publicWhite,
    success: Color(0xFF73E39B),
    warning: Color(0xFFFFA487),
    danger: Color(0xFFFF8C78),
    info: Color(0xFFC9C9CE),
    successForeground: Color(0xFF73E39B),
    infoForeground: Color(0xFFC9C9CE),
    warningForeground: Color(0xFFFFA487),
    dangerForeground: Color(0xFFFF8C78),
    successContainer: Color(0xFF123822),
    infoContainer: Color(0xFF2A2A2F),
    warningContainer: Color(0xFF472117),
    dangerContainer: Color(0xFF4B1D17),
    neutralContainer: Color(0xFF2A2A2F),
    textPrimary: Color(0xFFF7F7F8),
    textSecondary: Color(0xFFC9C9CE),
    textMuted: Color(0xFF9A9AA2),
  );

  Color get paper => canvas;
  Color get surfaceLow => surfaceMuted;
  Color get surfaceHigh => surfaceRaised;
  bool get _isDarkPalette => textPrimary.computeLuminance() > 0.5;
  Color get actionColor => _isDarkPalette ? publicWhite : publicBlack;
  Color get priorityColor => actionColor;
  Color get outlineSoft => borderSoft;
  Color get controlBorder =>
      Color.alphaBlend(textPrimary.withValues(alpha: 0.52), surfaceReadable);
  Color get successInk => successForeground;
  Color get dangerSoft => dangerForeground;
  Color get defaultGroupAccent => brandPeriwinkle;
  Color get brandFoundation => brandPaper;
  Color get brandSecondary => brandDustyRose;
  Color get brandAction => brandOrangeRed;
  Color get urgentAction => brandOrangeRed;
  Color get brandSuccess => brandMintGreen;
  Color get transparent => transparentColor;
  Color get onAccent => _isDarkPalette ? publicBlack : publicWhite;
  Color get selectedOnAccent => onAccent;
  Color get onImagePrimary => brandPaper;
  Color get onImageMuted => brandPaper.withValues(alpha: 0.72);
  Color get exportCanvas => brandPaper;
  Color get exportPaint => publicBlack;
  Color get shadowPaint => publicBlack;
  Color get imageScrimSoft => publicBlack.withValues(alpha: 0.18);
  Color get imageScrimStrong => publicBlack.withValues(alpha: 0.62);
  Color get cameraScrim => publicBlack.withValues(alpha: 0.58);
  Color get cameraScrimStrong => publicBlack.withValues(alpha: 0.72);
  Color get statusGranted => successForeground;
  Color get statusBlocked => dangerForeground;

  static const brandPrimaryOptions = <CollectPaletteOption>[
    CollectPaletteOption(brandPeriwinkle),
    CollectPaletteOption(brandMintGreen),
    CollectPaletteOption(brandDustyRose),
    CollectPaletteOption(brandOrangeRed),
  ];

  Color get screenBase => canvas;

  Color get panelSurface => surfaceReadable;

  Color get strongPanelSurface => surfaceRaised;

  Color get controlSurface => surfaceRaised;

  Color get panelBorder => transparentColor;

  Color get overlayScrim => publicBlack.withValues(alpha: 0.08);

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
  const CollectPaletteOption(this.color);

  final Color color;

  String get hex {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
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
