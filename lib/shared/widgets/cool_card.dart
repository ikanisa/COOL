import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import 'cool_press_feedback.dart';

/// Card variants — ROUGEBLACK design system.
enum CoolCardVariant {
  /// Default: solid surface with subtle border.
  default_,

  /// Glass: translucent with backdrop blur.
  glass,

  /// Outline: transparent with visible border.
  outline,

  /// Accent: primary tinted background with primary border.
  accent,
}

/// Card padding presets.
enum CoolCardPadding {
  none,
  sm,
  md,
  lg;

  EdgeInsets get insets => switch (this) {
    CoolCardPadding.none => EdgeInsets.zero,
    CoolCardPadding.sm => const EdgeInsets.all(CoolSpace.x3), // 12
    CoolCardPadding.md => const EdgeInsets.all(CoolSpace.x4), // 16
    CoolCardPadding.lg => const EdgeInsets.all(CoolSpace.x6), // 24
  };
}

/// A shared card surface — ROUGEBLACK system.
///
/// Flat borders (white/5), no claymorphism. 4 variants.
class CoolCard extends StatelessWidget {
  const CoolCard({
    required this.child,
    this.variant = CoolCardVariant.default_,
    this.cardPadding = CoolCardPadding.md,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.gradient,
    this.useGradient = false,
    this.blur = CoolBlur.subtle, // ROUGEBLACK default is 12.0
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final CoolCardVariant variant;
  final CoolCardPadding cardPadding;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final Gradient? gradient;
  final bool useGradient;
  final double blur;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final radius = borderRadius ?? CoolRadii.lg; // 16px default

    // Resolve decoration based on variant.
    final resolvedBg = backgroundColor ?? _variantBg(colors);
    final resolvedBorder = borderColor ?? _variantBorder(colors);
    final resolvedGradient =
        gradient ?? (useGradient ? colors.surfaceGradient : null);

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: resolvedBorder, width: 1),
    );

    final Widget content = Padding(
      padding: padding ?? cardPadding.insets,
      child: child,
    );

    // Glass variant uses backdrop filter.
    if (variant == CoolCardVariant.glass) {
      return _buildGlassCard(context, content, colors, radius, resolvedBorder);
    }

    final decoration = BoxDecoration(
      color: resolvedGradient == null ? resolvedBg : null,
      gradient: resolvedGradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: resolvedBorder, width: 1),
    );

    final card = Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? Ink(
              decoration: decoration,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(radius),
                splashColor: colors.accent.withValues(alpha: 0.06),
                highlightColor: Colors.transparent,
                child: content,
              ),
            )
          : DecoratedBox(decoration: decoration, child: content),
    );

    if (onTap != null) {
      return Semantics(
        label: semanticsLabel,
        button: true,
        child: CoolPressFeedback(onTap: onTap!, child: card),
      );
    }

    return card;
  }

  Widget _buildGlassCard(
    BuildContext context,
    Widget content,
    CoolSemanticColors colors,
    double radius,
    Color borderCol,
  ) {
    // Glass variant specifically uses the ROUGEBLACK specs
    // Opacity: 0.06 (via colors.glassSurface), Blur: 12, Border: 0.15.
    final glass = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassSurface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: RsColors.glassBorderOpacity,
              ),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: onTap == null
                ? content
                : InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(radius),
                    splashColor: colors.accent.withValues(alpha: 0.05),
                    highlightColor: Colors.transparent,
                    child: content,
                  ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      return CoolPressFeedback(onTap: onTap!, child: glass);
    }
    return glass;
  }

  Color _variantBg(CoolSemanticColors colors) => switch (variant) {
    CoolCardVariant.default_ => colors.cardSurface,
    CoolCardVariant.glass => colors.glassSurface,
    CoolCardVariant.outline => Colors.transparent,
    CoolCardVariant.accent => colors.accent.withValues(alpha: 0.05),
  };

  Color _variantBorder(CoolSemanticColors colors) => switch (variant) {
    CoolCardVariant.default_ => Colors.white.withValues(alpha: 0.05),
    CoolCardVariant.glass => Colors.white.withValues(
      alpha: RsColors.glassBorderOpacity,
    ),
    CoolCardVariant.outline => Colors.white.withValues(alpha: 0.10),
    CoolCardVariant.accent => colors.accent.withValues(alpha: 0.20),
  };
}
