import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Horizontal scrollable filter chip rail for admin surfaces.
///
/// Renders a row of [FilterChip]-style pills that scroll horizontally.
/// Extracted from recurring admin patterns in sender inventory and
/// manual review sections.
class AdminFilterRail extends StatelessWidget {
  const AdminFilterRail({
    required this.filters,
    required this.selectedIndices,
    required this.onSelected,
    super.key,
  });

  /// Labels for each filter chip.
  final List<String> filters;

  /// Currently selected indices.
  final Set<int> selectedIndices;

  /// Called when a chip's selection state changes.
  final void Function(int index, bool selected) onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(filters.length, (index) {
          final isSelected = selectedIndices.contains(index);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                filters[index],
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isSelected ? colors.primaryText : colors.secondaryText,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) => onSelected(index, selected),
              selectedColor: colors.accent.withValues(alpha: 0.18),
              backgroundColor: colors.cardSurface,
              checkmarkColor: colors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CoolRadii.pill),
                side: BorderSide(
                  color: isSelected ? colors.accent : colors.border,
                ),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          );
        }),
      ),
    );
  }
}
