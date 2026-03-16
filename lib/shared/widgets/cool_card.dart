import 'package:flutter/material.dart';

import '../../core/theme/cool_palette.dart';

/// A reusable themed card used throughout the Cool app.
///
/// Cards default to a flatter surface so screens can carry more content
/// without feeling overly decorative.
class CoolCard extends StatelessWidget {
  const CoolCard({
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.gradient,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? borderRadius;
  final Gradient? gradient;

  /// Accessibility label for screen readers. If null and [onTap] is set,
  /// screen readers will still announce this as a tappable element.
  final String? semanticsLabel;

  static const _defaultRadius = 28.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final radius = borderRadius ?? _defaultRadius;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? palette.border, width: 1.0),
    );
    final decoration = ShapeDecoration(
      shape: shape,
      color: gradient == null ? (backgroundColor ?? palette.surface2) : null,
      gradient: gradient,
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );

    final Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(18),
      child: child,
    );

    if (onTap != null) {
      return Semantics(
        label: semanticsLabel,
        button: true,
        child: Material(
          color: Colors.transparent,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: decoration,
            child: InkWell(
              onTap: onTap,
              splashColor: palette.accent.withValues(alpha: 0.08),
              highlightColor: Colors.transparent,
              child: content,
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(decoration: decoration, child: content),
    );
  }
}
