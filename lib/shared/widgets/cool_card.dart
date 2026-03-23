import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// A reusable premium surface card with tonal separation instead of visible borders.
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

  static const _defaultRadius = 24.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final brightness = Theme.of(context).brightness;
    final isLight = brightness == Brightness.light;
    final radius = borderRadius ?? _defaultRadius;
    final hasBorder = borderColor != null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: hasBorder
          ? BorderSide(color: borderColor!, width: 1.1)
          : BorderSide.none,
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
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Colors.white.withValues(alpha: isLight ? 0.16 : 0.08),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isLight ? 0.00 : 0.04),
                  ],
                  stops: const <double>[0, 0.34, 1],
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
              splashColor: colors.buttonPrimaryBackground.withValues(
                alpha: 0.06,
              ),
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
