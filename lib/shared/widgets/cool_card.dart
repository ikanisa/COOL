import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A reusable dark-surface card used throughout the Cool app.
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

  static const _defaultRadius = 20.0;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? _defaultRadius;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? AppColors.border),
    );
    final decoration = ShapeDecoration(
      shape: shape,
      color: gradient == null ? (backgroundColor ?? AppColors.surface2) : null,
      gradient: gradient,
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

    Widget content = Padding(
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
              splashColor: AppColors.accent.withValues(alpha: 0.08),
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
