import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../partners/providers/rayon_sports_provider.dart';

String fmtAmt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

Future<void> ensureHomeMembership(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(rayonSportsProvider.notifier);
  try {
    final result = await notifier.ensureMembership();
    if (!context.mounted) return;
    CoolToast.info(context, result.message);
  } catch (error) {
    if (!context.mounted) return;
    CoolToast.error(context, error.toString());
  }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: barHeight,
          width: constraints.maxWidth,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
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
    final card = Container(
      padding: const EdgeInsets.all(CoolSpace.x5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CoolRadii.xl),
          onTap: onTap,
          child: card,
        ),
      );
    }
    return card;
  }
}

class HomeBluTag extends StatelessWidget {
  const HomeBluTag({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: RsColors.rsBlue.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        border: Border.all(
          color: RsColors.rsBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: context.coolText.mono(
          Theme.of(context).textTheme.labelSmall,
          fontWeight: FontWeight.w800,
          color: RsColors.rsBlue,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
