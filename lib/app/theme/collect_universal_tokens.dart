import 'dart:ui';

import 'package:flutter/material.dart';

import 'collect_colors.dart';
import 'collect_motion.dart';
import 'collect_radius.dart';
import 'collect_spacing.dart';

class CollectUniversalTokens extends ThemeExtension<CollectUniversalTokens> {
  const CollectUniversalTokens({
    required this.chromeDefault,
    required this.chromeMuted,
    required this.actionPrimary,
    required this.actionPill,
    required this.actionDestructive,
    required this.focusRing,
    required this.adminRail,
    required this.adminWorkspace,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusDanger,
    required this.statusInfo,
    required this.spacingStep,
    required this.touchTarget,
    required this.iconTarget,
    required this.cardRadius,
    required this.controlRadius,
    required this.focusRingWidth,
    required this.adminRailWidth,
    required this.motionFast,
    required this.motionStandard,
    required this.motionSlow,
    required this.densityScale,
    required this.highContrast,
  });

  final Color chromeDefault;
  final Color chromeMuted;
  final Color actionPrimary;
  final Color actionPill;
  final Color actionDestructive;
  final Color focusRing;
  final Color adminRail;
  final Color adminWorkspace;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusDanger;
  final Color statusInfo;
  final double spacingStep;
  final double touchTarget;
  final double iconTarget;
  final double cardRadius;
  final double controlRadius;
  final double focusRingWidth;
  final double adminRailWidth;
  final Duration motionFast;
  final Duration motionStandard;
  final Duration motionSlow;
  final double densityScale;
  final bool highContrast;

  static CollectUniversalTokens fromColors(
    CollectColors colors,
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final focus = highContrast
        ? (isDark ? CollectColors.brandPaper : CollectColors.publicBlack)
        : colors.focusRing;
    return CollectUniversalTokens(
      chromeDefault: CollectColors.referenceChromeBlack,
      chromeMuted: CollectColors.referenceChromeBlack.withValues(
        alpha: isDark ? 0.82 : 0.72,
      ),
      actionPrimary: colors.actionColor,
      actionPill: isDark ? CollectColors.brandPaper : CollectColors.publicBlack,
      actionDestructive: colors.dangerForeground,
      focusRing: focus,
      adminRail: CollectColors.referenceChromeBlack,
      adminWorkspace: colors.canvas,
      statusSuccess: colors.successForeground,
      statusWarning: colors.warningForeground,
      statusDanger: colors.dangerForeground,
      statusInfo: colors.infoForeground,
      spacingStep: CollectSpacing.x1,
      touchTarget: CollectSpacing.target,
      iconTarget: CollectSpacing.iconTarget,
      cardRadius: CollectRadius.md,
      controlRadius: CollectRadius.pill,
      focusRingWidth: highContrast ? 3 : 2,
      adminRailWidth: 260,
      motionFast: CollectMotion.fast,
      motionStandard: CollectMotion.medium,
      motionSlow: CollectMotion.slow,
      densityScale: isDark ? 1 : 0.96,
      highContrast: highContrast,
    );
  }

  static CollectUniversalTokens highContrastLight() {
    return fromColors(
      CollectColors.light,
      Brightness.light,
      highContrast: true,
    );
  }

  static CollectUniversalTokens highContrastDark() {
    return fromColors(CollectColors.dark, Brightness.dark, highContrast: true);
  }

  @override
  CollectUniversalTokens copyWith({
    Color? chromeDefault,
    Color? chromeMuted,
    Color? actionPrimary,
    Color? actionPill,
    Color? actionDestructive,
    Color? focusRing,
    Color? adminRail,
    Color? adminWorkspace,
    Color? statusSuccess,
    Color? statusWarning,
    Color? statusDanger,
    Color? statusInfo,
    double? spacingStep,
    double? touchTarget,
    double? iconTarget,
    double? cardRadius,
    double? controlRadius,
    double? focusRingWidth,
    double? adminRailWidth,
    Duration? motionFast,
    Duration? motionStandard,
    Duration? motionSlow,
    double? densityScale,
    bool? highContrast,
  }) {
    return CollectUniversalTokens(
      chromeDefault: chromeDefault ?? this.chromeDefault,
      chromeMuted: chromeMuted ?? this.chromeMuted,
      actionPrimary: actionPrimary ?? this.actionPrimary,
      actionPill: actionPill ?? this.actionPill,
      actionDestructive: actionDestructive ?? this.actionDestructive,
      focusRing: focusRing ?? this.focusRing,
      adminRail: adminRail ?? this.adminRail,
      adminWorkspace: adminWorkspace ?? this.adminWorkspace,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusWarning: statusWarning ?? this.statusWarning,
      statusDanger: statusDanger ?? this.statusDanger,
      statusInfo: statusInfo ?? this.statusInfo,
      spacingStep: spacingStep ?? this.spacingStep,
      touchTarget: touchTarget ?? this.touchTarget,
      iconTarget: iconTarget ?? this.iconTarget,
      cardRadius: cardRadius ?? this.cardRadius,
      controlRadius: controlRadius ?? this.controlRadius,
      focusRingWidth: focusRingWidth ?? this.focusRingWidth,
      adminRailWidth: adminRailWidth ?? this.adminRailWidth,
      motionFast: motionFast ?? this.motionFast,
      motionStandard: motionStandard ?? this.motionStandard,
      motionSlow: motionSlow ?? this.motionSlow,
      densityScale: densityScale ?? this.densityScale,
      highContrast: highContrast ?? this.highContrast,
    );
  }

  @override
  CollectUniversalTokens lerp(
    ThemeExtension<CollectUniversalTokens>? other,
    double t,
  ) {
    if (other is! CollectUniversalTokens) return this;
    return CollectUniversalTokens(
      chromeDefault: Color.lerp(chromeDefault, other.chromeDefault, t)!,
      chromeMuted: Color.lerp(chromeMuted, other.chromeMuted, t)!,
      actionPrimary: Color.lerp(actionPrimary, other.actionPrimary, t)!,
      actionPill: Color.lerp(actionPill, other.actionPill, t)!,
      actionDestructive: Color.lerp(
        actionDestructive,
        other.actionDestructive,
        t,
      )!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      adminRail: Color.lerp(adminRail, other.adminRail, t)!,
      adminWorkspace: Color.lerp(adminWorkspace, other.adminWorkspace, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      spacingStep: lerpDouble(spacingStep, other.spacingStep, t)!,
      touchTarget: lerpDouble(touchTarget, other.touchTarget, t)!,
      iconTarget: lerpDouble(iconTarget, other.iconTarget, t)!,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      controlRadius: lerpDouble(controlRadius, other.controlRadius, t)!,
      focusRingWidth: lerpDouble(focusRingWidth, other.focusRingWidth, t)!,
      adminRailWidth: lerpDouble(adminRailWidth, other.adminRailWidth, t)!,
      motionFast: _lerpDuration(motionFast, other.motionFast, t),
      motionStandard: _lerpDuration(motionStandard, other.motionStandard, t),
      motionSlow: _lerpDuration(motionSlow, other.motionSlow, t),
      densityScale: lerpDouble(densityScale, other.densityScale, t)!,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
    );
  }

  static Duration _lerpDuration(Duration a, Duration b, double t) {
    return Duration(
      microseconds: lerpDouble(
        a.inMicroseconds.toDouble(),
        b.inMicroseconds.toDouble(),
        t,
      )!.round(),
    );
  }
}

extension CollectUniversalTokensTheme on BuildContext {
  CollectUniversalTokens get collectUniversalTokens {
    final theme = Theme.of(this);
    return theme.extension<CollectUniversalTokens>() ??
        CollectUniversalTokens.fromColors(collectColors, theme.brightness);
  }
}
