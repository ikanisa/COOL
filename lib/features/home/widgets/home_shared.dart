import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_card.dart';

String fmtAmt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

class HomeProgressBar extends StatelessWidget {
  const HomeProgressBar({
    super.key,
    required this.value,
    required this.barColor,
    this.barHeight = 4,
  });

  final double value;
  final Color barColor;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: barHeight,
          width: constraints.maxWidth,
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(barHeight / 2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth * value.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(barHeight / 2),
                boxShadow: [
                  BoxShadow(
                    color: barColor.withValues(alpha: 0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class HomeGlassCard extends StatelessWidget {
  const HomeGlassCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      variant: CoolCardVariant.glass,
      cardPadding: CoolCardPadding.none,
      padding: const EdgeInsets.all(CoolSpace.x5),
      backgroundColor: colors.glassSurface,
      borderColor: colors.border,
      onTap: onTap,
      child: child,
    );
  }
}

class HomeAccentTag extends StatelessWidget {
  const HomeAccentTag({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        border: Border.all(color: colors.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: context.coolText.mono(
          Theme.of(context).textTheme.labelSmall,
          fontWeight: FontWeight.w800,
          color: colors.accent,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
