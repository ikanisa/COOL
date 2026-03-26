import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_press_feedback.dart';

/// A reusable premium surface card with tonal separation instead of visible borders.
///
/// When [onTap] is set, wraps content in [CoolPressFeedback] for tactile
/// scale + opacity animation on press.
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

    // Use CoolGlassOpacity tokens for the clay gradient overlay.
    final clayAlpha = CoolGlassOpacity.clayGradientWhite(brightness);

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
                    Colors.white.withValues(alpha: clayAlpha),
                    Colors.transparent,
                    Colors.black.withValues(
                      alpha: brightness == Brightness.dark ? 0.04 : 0.00,
                    ),
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

    final card = Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap != null
          ? Ink(
              decoration: decoration,
              child: InkWell(
                onTap: onTap,
                splashColor: colors.buttonPrimaryBackground.withValues(
                  alpha: 0.06,
                ),
                highlightColor: Colors.transparent,
                child: content,
              ),
            )
          : Ink(decoration: decoration, child: content),
    );

    // Wrap tappable cards with press feedback for tactile scale + opacity.
    if (onTap != null) {
      return Semantics(
        label: semanticsLabel,
        button: true,
        child: CoolPressFeedback(
          onTap: onTap!,
          child: card,
        ),
      );
    }

    return card;
  }
}

