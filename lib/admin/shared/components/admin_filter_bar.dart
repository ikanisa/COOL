import 'package:flutter/material.dart';

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
    return Wrap(
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
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
        Semantics(
          label: 'Admin queue status filter',
          hint: 'Limits results to the selected queue state.',
          child: SegmentedButton<String>(
            segments: [
              for (final option in statusOptions)
                ButtonSegment(value: option.value, label: Text(option.label)),
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
            decoration: const InputDecoration(
              labelText: 'Sort',
              prefixIcon: Icon(Icons.sort),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final option in sortOptions)
                DropdownMenuItem(
                  value: option.value,
                  child: Text(option.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              if (value != null) onSortChanged(value);
            },
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Refresh',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class AdminFilterOption {
  const AdminFilterOption({required this.value, required this.label});

  final String value;
  final String label;
}
