import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';


/// A frosted glass surface — ROUGEBLACK design system.
///
/// Renders a [BackdropFilter]-based glassmorphic card with configurable
/// blur, opacity, border, and optional gradient accent. Designed to sit
/// over deep navy or gradient backgrounds — never on white/light surfaces.
///
/// ```dart
/// GlassCard(
///   child: Text('Content'),
///   gradientAccent: Colors.red,
/// )
/// ```
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.blur = 12.0,
    this.opacity = 0.06,
    this.borderOpacity = 0.10,
    this.borderRadius = CoolRadii.lg,
    this.gradientAccent,
    this.padding,
    this.margin,
    this.onTap,
    this.semanticsLabel,
    super.key,
  });

  /// The content inside the glass surface.
  final Widget child;

  /// Backdrop blur sigma. Default 12.
  final double blur;

  /// Background white opacity (0–1). Default 0.06.
  final double opacity;

  /// Border white opacity (0–1). Default 0.15.
  final double borderOpacity;

  /// Corner radius. Default 28.
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
    final glassBg = Colors.white.withValues(alpha: opacity);
    final glassBorder = Colors.white.withValues(alpha: borderOpacity);

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

    final card = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: glassBg,
            gradient: gradient,
            borderRadius: br,
            border: Border.all(color: glassBorder, width: 1),
          ),
          child: content,
        ),
      ),
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
