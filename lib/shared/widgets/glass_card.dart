import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A frosted glass surface — Tactile Monolith design system.
///
/// Renders a [BackdropFilter]-based glassmorphic card with configurable
/// blur, opacity, border, and optional gradient accent. Designed to sit
/// over deep violet backgrounds — never on white/light surfaces.
///
/// Default: 60% opacity, 40px blur, violet ghost border at 15%.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.blur = CoolBlur.glass,
    this.opacity = 0.60,
    this.borderOpacity = 0.15,
    this.borderRadius = CoolRadii.xl,
    this.gradientAccent,
    this.padding,
    this.margin,
    this.onTap,
    this.semanticsLabel,
    super.key,
  });

  /// The content inside the glass surface.
  final Widget child;

  /// Backdrop blur sigma. Default [CoolBlur.glass] = 40.
  final double blur;

  /// Background opacity (0–1). Default 0.60 per Tactile Monolith.
  final double opacity;

  /// Ghost border opacity (0–1). Default 0.15.
  final double borderOpacity;

  /// Corner radius. Default 48 (xl — molded clay).
  final double borderRadius;

  /// Optional accent color for a subtle top-left gradient wash.
  /// Optional accent color for a subtle top-left gradient wash.
  final Color? gradientAccent;

  /// Inner padding.
  final EdgeInsets? padding;

  /// Outer margin.
  final EdgeInsets? margin;

  /// Tap callback. Adds press feedback + InkWell.
  final VoidCallback? onTap;

  /// Accessibility label.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(borderRadius);
    final colors = context.coolSemanticColors;
    final glassBg = colors.glassSurface.withValues(alpha: opacity);

    // Optionally add a subtle gradient wash from the accent color.
    final gradient = gradientAccent != null
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradientAccent!.withValues(alpha: 0.08),
              Colors.transparent,
            ],
          )
        : null;

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(CoolSpace.x4),
      child: child,
    );

    // Wrap tappable cards in Material/InkWell for ripple.
    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          splashColor: (gradientAccent ?? Colors.white).withValues(alpha: 0.05),
          highlightColor: Colors.transparent,
          child: content,
        ),
      );
    }

    // Skip expensive BackdropFilter when reduced motion is requested
    // (accessibility setting) to prevent jank on low-end devices.
    final mediaQuery = MediaQuery.of(context);
    final reduceBlur = mediaQuery.disableAnimations ||
        mediaQuery.accessibleNavigation;
    final effectiveBlur = reduceBlur ? 0.0 : blur;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: glassBg,
        gradient: gradient,
        borderRadius: br,
        boxShadow: CoolShadows.glass(strength: 0.72),
        // Ghost border: violet-tinted, not white
        border: Border.all(
          color: colors.borderStrong.withValues(alpha: borderOpacity),
          width: 0.9,
        ),
      ),
      child: content,
    );

    if (effectiveBlur > 0) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: surface,
      );
    }

    final card = ClipRRect(
      borderRadius: br,
      child: surface,
    );

    final result = margin != null
        ? Padding(padding: margin!, child: card)
        : card;

    if (semanticsLabel != null) {
      return Semantics(
        label: semanticsLabel,
        button: onTap != null,
        child: result,
      );
    }

    return result;
  }
}
