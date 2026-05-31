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
    navy: Color(0xFF121212),
    blue: Color(0xFFFF005E),
    aqua: Color(0xFFB90042),
    coral: Color(0xFFBA1A1A),
    lime: Color(0xFF006A3C),
    purple: Color(0xFF5D3E42),
    surface: Color(0xFFFCF9F8),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F5F5),
    border: Color(0xFFEEEEEE),
    success: Color(0xFF138A58),
    warning: Color(0xFFAC6900),
    danger: Color(0xFFBA1A1A),
    info: Color(0xFFB90042),
    textPrimary: Color(0xFF1C1B1B),
    textSecondary: Color(0xFF5D3E42),
    textMuted: Color(0xFF926E71),
  );

  static const dark = CollectColors(
    ink: Color(0xFFF3F0EF),
    navy: Color(0xFFF3F0EF),
    blue: Color(0xFFFFB2BB),
    aqua: Color(0xFFFFB2BB),
    coral: Color(0xFFFFDAD6),
    lime: Color(0xFF84FAB1),
    purple: Color(0xFFE7BCC0),
    surface: Color(0xFF121212),
    surfaceRaised: Color(0xFF1C1B1B),
    surfaceMuted: Color(0xFF313030),
    border: Color(0xFF3F3D3D),
    success: Color(0xFF5CD68E),
    warning: Color(0xFFFFC95C),
    danger: Color(0xFFFFB4AB),
    info: Color(0xFFFFB2BB),
    textPrimary: Color(0xFFF3F0EF),
    textSecondary: Color(0xFFE7BCC0),
    textMuted: Color(0xFFDCD9D9),
  );

  bool get isDark => surface.computeLuminance() < 0.2;

  Color statusBackground(CollectStatusTone tone) {
    final alpha = isDark ? 0.22 : 0.12;
    return switch (tone) {
      CollectStatusTone.success => success.withValues(alpha: alpha),
      CollectStatusTone.warning => warning.withValues(alpha: alpha),
      CollectStatusTone.danger => danger.withValues(alpha: alpha),
      CollectStatusTone.info => info.withValues(alpha: alpha),
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
