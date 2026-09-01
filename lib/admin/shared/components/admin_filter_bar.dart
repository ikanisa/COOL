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
    Widget searchField() => SizedBox(
      child: Semantics(
        textField: true,
        label: 'Search admin queue',
        hint:
            'Filters the current admin queue by record, reference, or operator context.',
        child: TextField(
          controller: searchController,
          onSubmitted: (_) => onRefresh(),
          decoration: InputDecoration(
            hintText: 'Search',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: colors.surfaceRaised.withValues(alpha: 0.62),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );

    String selectedLabel(List<AdminFilterOption> options, String value) {
      for (final option in options) {
        if (option.value == value) return option.label;
      }
      return '';
    }

    final statusLabel = selectedLabel(statusOptions, status);
    final sortLabel = selectedLabel(sortOptions, sortBy);
    final statusFilter = _AdminFilterMenu(
      key: const Key('admin-status-filter-select'),
      tooltip: 'Filter: ${statusLabel.isEmpty ? 'All' : statusLabel}',
      semanticLabel:
          'Status filter, ${statusLabel.isEmpty ? 'All' : statusLabel} selected',
      icon: status.isEmpty
          ? Icons.filter_alt_outlined
          : Icons.filter_alt_rounded,
      selectedValue: status,
      options: statusOptions,
      onSelected: onStatusChanged,
    );
    final sortFilter = _AdminFilterMenu(
      tooltip: 'Sort: ${sortLabel.isEmpty ? 'Newest' : sortLabel}',
      semanticLabel:
          'Sort order, ${sortLabel.isEmpty ? 'Newest' : sortLabel} selected',
      icon: Icons.sort_rounded,
      selectedValue: sortBy,
      options: sortOptions,
      onSelected: onSortChanged,
    );

    final refreshButton = IconButton.filled(
      tooltip: 'Refresh',
      style: IconButton.styleFrom(
        backgroundColor: colors.textPrimary,
        foregroundColor: colors.surfaceReadable,
      ),
      onPressed: onRefresh,
      icon: const Icon(Icons.refresh),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceReadable.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(child: searchField()),
            const SizedBox(width: 8),
            statusFilter,
            const SizedBox(width: 4),
            sortFilter,
            const SizedBox(width: 4),
            refreshButton,
          ],
        ),
      ),
    );
  }
}

class _AdminFilterMenu extends StatelessWidget {
  const _AdminFilterMenu({
    required this.tooltip,
    required this.semanticLabel,
    required this.icon,
    required this.selectedValue,
    required this.options,
    required this.onSelected,
    super.key,
  });

  final String tooltip;
  final String semanticLabel;
  final IconData icon;
  final String selectedValue;
  final List<AdminFilterOption> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: PopupMenuButton<String>(
        tooltip: tooltip,
        initialValue: selectedValue,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem<String>(
              value: option.value,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: option.value == selectedValue
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(option.label),
                ],
              ),
            ),
        ],
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            border: Border.all(
              color: CollectRuntimeTokens.controlBorder(colors),
            ),
          ),
          child: SizedBox.square(
            dimension: 46,
            child: Icon(icon, size: 20, color: colors.textPrimary),
          ),
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
