import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_card.dart';
import 'cool_icon_box.dart';

/// Data class for a quick action tile.
class CoolQuickAction {
  const CoolQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
    this.iconWidget,
  });

  /// Icon data for the tile.
  final IconData icon;

  /// Short label (1–3 words max).
  final String label;

  /// Tap handler.
  final VoidCallback onTap;

  /// Optional accent color override for the icon box.
  final Color? accent;

  /// Optional custom icon widget (e.g., SVG) instead of [icon].
  final Widget? iconWidget;
}

/// A standardized 2×N grid of icon-led compact action tiles.
///
/// Replaces bespoke `HomeQuickServices` and `_BiopayActionTile` grid layouts.
///
/// ```dart
/// CoolQuickActionGrid(
///   actions: [
///     CoolQuickAction(icon: CoolIcons.contribute, label: 'Save', onTap: ...),
///     CoolQuickAction(icon: CoolIcons.qrScan, label: 'Scan', onTap: ...),
///   ],
/// )
/// ```
class CoolQuickActionGrid extends StatelessWidget {
  const CoolQuickActionGrid({
    required this.actions,
    this.crossAxisCount = 2,
    this.spacing,
    super.key,
  });

  /// The list of quick actions to display.
  final List<CoolQuickAction> actions;

  /// Number of columns (default: 2 for mobile).
  final int crossAxisCount;

  /// Spacing between tiles (default: CoolSpace.x3).
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final resolvedSpacing = spacing ?? CoolSpace.x3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalSpacing = resolvedSpacing * (crossAxisCount - 1);
        final tileWidth =
            (constraints.maxWidth - totalSpacing) / crossAxisCount;

        return Wrap(
          spacing: resolvedSpacing,
          runSpacing: resolvedSpacing,
          children: [
            for (final action in actions)
              SizedBox(
                width: tileWidth,
                child: _QuickActionTile(action: action),
              ),
          ],
        );
      },
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});

  final CoolQuickAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final tileHeight = 120.0 + (textScale > 1 ? (textScale - 1) * 36.0 : 0.0);

    return Semantics(
      button: true,
      label: action.label,
      child: CoolCard(
        onTap: action.onTap,
        cardPadding: CoolCardPadding.none,
        padding: const EdgeInsets.all(CoolSpace.x4),
        child: SizedBox(
          height: tileHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CoolIconBox(
                    icon: action.icon,
                    accent: action.accent ?? colors.accent,
                    size: CoolIconBoxSize.md,
                    iconWidget: action.iconWidget,
                  ),
                  const Spacer(),
                  Icon(
                    CoolIcons.forward,
                    size: 18,
                    color: colors.tertiaryText,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                action.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.headline(
                  theme.textTheme.titleMedium,
                  color: colors.primaryText,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
