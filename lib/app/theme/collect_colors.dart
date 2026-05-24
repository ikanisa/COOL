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
    ink: Color(0xFF10131A),
    navy: Color(0xFF101B34),
    blue: Color(0xFF3157F6),
    aqua: Color(0xFF078A9A),
    coral: Color(0xFFFF6257),
    lime: Color(0xFF4F8B2C),
    purple: Color(0xFF6F57D9),
    surface: Color(0xFFF5F7FB),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEAF0F7),
    border: Color(0xFFD9E2EC),
    success: Color(0xFF138A58),
    warning: Color(0xFFAC6900),
    danger: Color(0xFFC83A31),
    info: Color(0xFF225CCB),
    textPrimary: Color(0xFF10131A),
    textSecondary: Color(0xFF48556A),
    textMuted: Color(0xFF687487),
  );

  static const dark = CollectColors(
    ink: Color(0xFFF5F7FB),
    navy: Color(0xFFC8D6FF),
    blue: Color(0xFF8EA7FF),
    aqua: Color(0xFF5FD8E3),
    coral: Color(0xFFFF978F),
    lime: Color(0xFF9BD66D),
    purple: Color(0xFFB9AAFF),
    surface: Color(0xFF080D16),
    surfaceRaised: Color(0xFF101827),
    surfaceMuted: Color(0xFF182337),
    border: Color(0xFF2B384D),
    success: Color(0xFF5CD68E),
    warning: Color(0xFFFFC95C),
    danger: Color(0xFFFF8078),
    info: Color(0xFF9CB9FF),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFC7D2E1),
    textMuted: Color(0xFF98A7BA),
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
