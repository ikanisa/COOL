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
    ink: Color(0xFF0F172A),
    navy: Color(0xFF111827),
    blue: Color(0xFF2563EB),
    aqua: Color(0xFF0F766E),
    coral: Color(0xFFF97316),
    lime: Color(0xFF16A34A),
    purple: Color(0xFF7C3AED),
    surface: Color(0xFFF8FAFC),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFF6FF),
    border: Color(0xFFD8E2F0),
    success: Color(0xFF059669),
    warning: Color(0xFFB45309),
    danger: Color(0xFFDC2626),
    info: Color(0xFF2563EB),
    textPrimary: Color(0xFF111827),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF64748B),
  );

  static const dark = CollectColors(
    ink: Color(0xFFF8FAFC),
    navy: Color(0xFFE2E8F0),
    blue: Color(0xFF93C5FD),
    aqua: Color(0xFF5EEAD4),
    coral: Color(0xFFFDBA74),
    lime: Color(0xFF86EFAC),
    purple: Color(0xFFC4B5FD),
    surface: Color(0xFF0F172A),
    surfaceRaised: Color(0xFF172033),
    surfaceMuted: Color(0xFF1E293B),
    border: Color(0xFF334155),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFCA5A5),
    info: Color(0xFF93C5FD),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFFCBD5E1),
    textMuted: Color(0xFF94A3B8),
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
