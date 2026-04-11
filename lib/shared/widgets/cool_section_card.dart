import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_card.dart';

/// A card that groups related content with an optional section label.
class CoolSectionCard extends StatelessWidget {
  const CoolSectionCard({
    required this.children,
    this.sectionLabel,
    this.variant = CoolCardVariant.default_,
    this.cardPadding,
    this.spacing,
    this.backgroundColor,
    this.borderRadius,
    super.key,
  });

  const CoolSectionCard.glass({
    required this.children,
    this.sectionLabel,
    this.cardPadding,
    this.spacing,
    this.backgroundColor,
    this.borderRadius,
    super.key,
  }) : variant = CoolCardVariant.glass;

  final String? sectionLabel;

  final CoolCardVariant variant;

  final List<Widget> children;

  final EdgeInsets? cardPadding;

  final double? spacing;

  final Color? backgroundColor;

  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final resolvedSpacing = spacing ?? CoolSpace.x1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (sectionLabel != null) ...[
          Text(
            sectionLabel!,
            style: text.mono(
              Theme.of(context).textTheme.labelSmall,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
        ],
        CoolCard(
          variant: variant,
          backgroundColor: backgroundColor,
          borderRadius: borderRadius ?? CoolRadii.xl,
          padding:
              cardPadding ??
              const EdgeInsets.symmetric(
                horizontal: CoolSpace.x5,
                vertical: CoolSpace.x2,
              ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: resolvedSpacing),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
