import 'package:flutter/material.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_radius.dart';

IconData collectStatusIcon(CollectStatusTone tone, IconData? override) {
  if (override != null) return override;
  return switch (tone) {
    CollectStatusTone.success => CollectIcons.check,
    CollectStatusTone.warning => CollectIcons.warning,
    CollectStatusTone.danger => CollectIcons.error,
    CollectStatusTone.info => CollectIcons.info,
    CollectStatusTone.privacy => CollectIcons.lock,
    CollectStatusTone.neutral => CollectIcons.info,
  };
}

class CollectToneIcon extends StatelessWidget {
  const CollectToneIcon({
    required this.icon,
    required this.tone,
    this.large = false,
    super.key,
  });

  final IconData icon;
  final CollectStatusTone tone;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = colors.statusForeground(tone);
    final background = isDark
        ? Color.alphaBlend(
            foreground.withValues(alpha: 0.16),
            colors.surfaceRaised,
          )
        : colors.statusBackground(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: CollectRadius.pillBorder,
        border: Border.all(
          color: foreground.withValues(alpha: isDark ? 0.20 : 0),
        ),
      ),
      child: SizedBox.square(
        dimension: large ? 56 : 40,
        child: Icon(icon, color: foreground, size: large ? 28 : 20),
      ),
    );
  }
}
