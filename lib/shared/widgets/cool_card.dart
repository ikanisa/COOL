import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A reusable premium surface card with restrained depth and stronger edge definition.
class CoolCard extends StatelessWidget {
  const CoolCard({
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.gradient,
    this.useGradient = true,
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

  final bool useGradient;

  final String? semanticsLabel;

  static const _defaultRadius = CoolRadii.xl;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final radius = borderRadius ?? _defaultRadius;
    final effectiveBorderColor =
        borderColor ?? colors.border.withValues(alpha: isLight ? 0.8 : 1);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: effectiveBorderColor, width: 1.1),
    );

    final Gradient? resolvedGradient;
    final Color? resolvedColor;
    if (backgroundColor != null) {
      resolvedGradient = null;
      resolvedColor = backgroundColor;
    } else if (gradient != null) {
      resolvedGradient = gradient;
      resolvedColor = null;
    } else if (useGradient) {
      resolvedGradient = colors.surfaceGradient;
      resolvedColor = null;
    } else {
      resolvedGradient = null;
      resolvedColor = colors.cardSurface;
    }

    final decoration = ShapeDecoration(
      shape: shape,
      color: resolvedGradient == null
          ? (resolvedColor ?? colors.cardSurface)
          : null,
      gradient: resolvedGradient,
      shadows: CoolShadows.clay(brightness),
    );

    final Widget content = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: isLight ? 0.28 : 0.06),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isLight ? 0.01 : 0.05),
                  ],
                  stops: const [0, 0.28, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(padding: padding ?? CoolSpace.sectionPadding, child: child),
      ],
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
              splashColor: colors.accent.withValues(alpha: 0.08),
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
