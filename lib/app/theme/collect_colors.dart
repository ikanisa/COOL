import 'package:flutter/material.dart';

class CollectColors extends ThemeExtension<CollectColors> {
  const CollectColors({
    required this.ink,
    required this.navy,
    required this.blue,
    required this.aqua,
    required this.coral,
    required this.lime,
    required this.purple,
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

  final Color ink;
  final Color navy;
  final Color blue;
  final Color aqua;
  final Color coral;
  final Color lime;
  final Color purple;
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

  static const light = CollectColors(
    ink: Color(0xFF121212),
    navy: Color(0xFF1B1B1E),
    blue: Color(0xFFE70054),
    aqua: Color(0xFF00864E),
    coral: Color(0xFFFD5F7D),
    lime: Color(0xFF006A3C),
    purple: Color(0xFF5D3E42),
    surface: Color(0xFFFCF9F8),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF0EDEC),
    border: Color(0xFFE5E2E1),
    success: Color(0xFF006A3C),
    warning: Color(0xFF8A5A00),
    danger: Color(0xFFBA1A1A),
    info: Color(0xFFE70054),
    textPrimary: Color(0xFF1C1B1B),
    textSecondary: Color(0xFF5D3E42),
    textMuted: Color(0xFF926E71),
  );

  static const dark = CollectColors(
    ink: Color(0xFFF8FAFC),
    navy: Color(0xFFF3F0EF),
    blue: Color(0xFFFF5F89),
    aqua: Color(0xFF67DD97),
    coral: Color(0xFFFFB2BB),
    lime: Color(0xFF84FAB1),
    purple: Color(0xFFE7BCC0),
    surface: Color(0xFF151111),
    surfaceRaised: Color(0xFF211B1D),
    surfaceMuted: Color(0xFF312729),
    border: Color(0xFF5D3E42),
    success: Color(0xFF84FAB1),
    warning: Color(0xFFFFC65C),
    danger: Color(0xFFFFB4AB),
    info: Color(0xFFFF5F89),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFE5E2E1),
    textMuted: Color(0xFFC8C6C5),
  );

  Color get paper => surface;
  Color get surfaceLow => surfaceMuted;
  Color get surfaceHigh => surfaceRaised;
  Color get inkBlack => ink;
  Color get actionCrimson => blue;
  Color get criticalCrimson => info;
  Color get outlineSoft => border;
  Color get successInk => success;
  Color get dangerSoft => danger;

  bool get isDark => surface.computeLuminance() < 0.2;

  Color statusBackground(CollectStatusTone tone) {
    final alpha = isDark ? 0.24 : 0.10;
    return switch (tone) {
      CollectStatusTone.success => success.withValues(alpha: alpha),
      CollectStatusTone.warning => warning.withValues(alpha: alpha),
      CollectStatusTone.danger => danger.withValues(alpha: alpha),
      CollectStatusTone.info => actionCrimson.withValues(alpha: alpha),
      CollectStatusTone.privacy => purple.withValues(alpha: alpha),
      CollectStatusTone.neutral => surfaceMuted,
    };
  }

  Color statusForeground(CollectStatusTone tone) {
    return switch (tone) {
      CollectStatusTone.success => success,
      CollectStatusTone.warning => warning,
      CollectStatusTone.danger => danger,
      CollectStatusTone.info => info,
      CollectStatusTone.privacy => purple,
      CollectStatusTone.neutral => textSecondary,
    };
  }

  @override
  CollectColors copyWith({
    Color? ink,
    Color? navy,
    Color? blue,
    Color? aqua,
    Color? coral,
    Color? lime,
    Color? purple,
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
      ink: ink ?? this.ink,
      navy: navy ?? this.navy,
      blue: blue ?? this.blue,
      aqua: aqua ?? this.aqua,
      coral: coral ?? this.coral,
      lime: lime ?? this.lime,
      purple: purple ?? this.purple,
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
      ink: Color.lerp(ink, other.ink, t)!,
      navy: Color.lerp(navy, other.navy, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      aqua: Color.lerp(aqua, other.aqua, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
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

extension CollectColorsTheme on BuildContext {
  CollectColors get collectColors =>
      Theme.of(this).extension<CollectColors>() ?? CollectColors.light;
}
