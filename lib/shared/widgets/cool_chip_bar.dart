import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

class CoolChipItem {
  const CoolChipItem({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;
}

/// A horizontal scrollable chip/tab row.
class CoolChipBar extends StatelessWidget {
  const CoolChipBar({
    required this.items,
    this.scrollable = false,
    this.expand = true,
    this.spacing,
    this.padding,
    super.key,
  });

  final List<CoolChipItem> items;
  final bool scrollable;
  final bool expand;
  final double? spacing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final resolvedSpacing = spacing ?? CoolSpace.x2;

    final chips = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final chip = _CoolChip(item: items[i]);
      if (expand && !scrollable) {
        chips.add(Expanded(child: chip));
      } else {
        chips.add(chip);
      }
      if (i < items.length - 1) {
        chips.add(SizedBox(width: resolvedSpacing));
      }
    }

    final row = Row(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: chips,
    );

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding ?? EdgeInsets.zero,
        child: row,
      );
    }

    return Padding(padding: padding ?? EdgeInsets.zero, child: row);
  }
}

class _CoolChip extends StatelessWidget {
  const _CoolChip({required this.item});

  final CoolChipItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final isActive = item.isActive;

    return Semantics(
      label: item.label,
      button: true,
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          child: AnimatedContainer(
            duration: CoolMotion.quick,
            curve: CoolMotion.enterCurve,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? colors.chipSelectedBackground
                  : colors.chipBackground,
              borderRadius: BorderRadius.circular(CoolRadii.pill),
              border: Border.all(
                color: isActive
                    ? colors.accent.withValues(alpha: 0.24)
                    : colors.border,
              ),
              boxShadow: isActive
                  ? CoolShadows.primary(strength: 0.4)
                  : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 16,
                    color: isActive ? colors.primaryText : colors.secondaryText,
                  ),
                  const SizedBox(width: CoolSpace.x2),
                ],
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? colors.primaryText : colors.secondaryText,
                  ),
                ),
                if (item.count != null) ...[
                  const SizedBox(width: CoolSpace.x2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? colors.accent.withValues(alpha: 0.15)
                          : colors.cardSurfaceStrong,
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                    ),
                    child: Text(
                      '${item.count}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isActive ? colors.accent : colors.tertiaryText,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
