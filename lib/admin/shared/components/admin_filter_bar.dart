import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_runtime_tokens.dart';

class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    required this.searchController,
    required this.status,
    required this.sortBy,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onRefresh,
    this.statusOptions = const [
      AdminFilterOption(value: '', label: 'All'),
      AdminFilterOption(value: 'pending', label: 'Pending'),
      AdminFilterOption(value: 'active', label: 'Active'),
      AdminFilterOption(value: 'needs_review', label: 'Review'),
    ],
    this.sortOptions = const [
      AdminFilterOption(value: 'created_at_desc', label: 'Newest'),
      AdminFilterOption(value: 'created_at_asc', label: 'Oldest'),
    ],
    super.key,
  });

  final TextEditingController searchController;
  final String status;
  final String sortBy;
  final List<AdminFilterOption> statusOptions;
  final List<AdminFilterOption> sortOptions;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.borderAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: Semantics(
                textField: true,
                label: 'Search admin queue',
                hint:
                    'Filters the current admin queue by record, reference, or operator context.',
                child: TextField(
                  controller: searchController,
                  onSubmitted: (_) => onRefresh(),
                  decoration: InputDecoration(
                    labelText: 'Search',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: colors.surfaceMuted.withValues(alpha: 0.72),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              label: 'Admin queue status filter',
              hint: 'Limits results to the selected queue state.',
              child: SegmentedButton<String>(
                style: SegmentedButton.styleFrom(
                  backgroundColor: colors.surfaceMuted.withValues(alpha: 0.62),
                  selectedBackgroundColor: colors.textPrimary,
                  selectedForegroundColor: colors.surfaceReadable,
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(
                    color: CollectRuntimeTokens.controlBorder(colors),
                  ),
                ),
                segments: [
                  for (final option in statusOptions)
                    ButtonSegment(
                      value: option.value,
                      label: Text(option.label),
                    ),
                ],
                selected: {status},
                onSelectionChanged: (value) => onStatusChanged(value.single),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: sortBy,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Sort',
                  prefixIcon: const Icon(Icons.sort),
                  filled: true,
                  fillColor: colors.surfaceMuted.withValues(alpha: 0.72),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                items: [
                  for (final option in sortOptions)
                    DropdownMenuItem(
                      value: option.value,
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onSortChanged(value);
                },
              ),
            ),
            IconButton.filled(
              tooltip: 'Refresh',
              style: IconButton.styleFrom(
                backgroundColor: colors.textPrimary,
                foregroundColor: colors.surfaceReadable,
              ),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminFilterOption {
  const AdminFilterOption({required this.value, required this.label});

  final String value;
  final String label;
}
