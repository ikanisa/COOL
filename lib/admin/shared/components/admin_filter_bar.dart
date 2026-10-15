import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_radius.dart';
import '../../../app/theme/collect_runtime_tokens.dart';

class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    required this.searchController,
    required this.status,
    required this.sortBy,
    required this.onStatusChanged,
    required this.onSortChanged,
    required this.onRefresh,
    this.searchLabel = 'Search admin queue',
    this.searchHint = 'Search',
    this.searchExamples = const [],
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
  final String searchLabel;
  final String searchHint;
  final List<AdminSearchExample> searchExamples;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    Widget searchField() => SizedBox(
      child: MergeSemantics(
        child: Semantics(
          label: searchLabel,
          hint: 'Searches all matching records. Press Enter or Apply search.',
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: searchController,
            builder: (context, value, _) => TextField(
              key: const Key('admin-queue-search-input'),
              controller: searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onRefresh(),
              decoration: InputDecoration(
                hintText: searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value.text.isNotEmpty)
                      IconButton(
                        key: const Key('admin-queue-clear-search'),
                        tooltip: 'Clear search',
                        onPressed: () {
                          searchController.clear();
                          onRefresh();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    IconButton(
                      key: const Key('admin-queue-apply-search'),
                      tooltip: 'Apply search',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
                filled: true,
                fillColor: colors.surfaceRaised.withValues(alpha: 0.62),
                border: OutlineInputBorder(
                  borderRadius: CollectRadius.pillBorder,
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: CollectRadius.pillBorder,
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: CollectRadius.pillBorder,
                  borderSide: BorderSide(color: colors.focusRing, width: 2),
                ),
              ),
            ),
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
      key: const Key('admin-sort-filter-select'),
      tooltip: 'Sort: ${sortLabel.isEmpty ? 'Newest' : sortLabel}',
      semanticLabel:
          'Sort order, ${sortLabel.isEmpty ? 'Newest' : sortLabel} selected',
      icon: Icons.sort_rounded,
      selectedValue: sortBy,
      options: sortOptions,
      onSelected: onSortChanged,
    );

    final refreshButton = IconButton.filled(
      key: const Key('admin-queue-refresh'),
      constraints: const BoxConstraints.tightFor(
        width: kMinInteractiveDimension,
        height: kMinInteractiveDimension,
      ),
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
        borderRadius: CollectRadius.cardBorder,
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Measure at the actual input font size, not scale(1), so nonlinear
            // text scaling also gets a full-width search field when needed.
            final fontSize =
                Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0;
            final enlargedText =
                MediaQuery.textScalerOf(context).scale(fontSize) >
                fontSize * 1.3;
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            const spacing = 4.0;
            final controlCount = searchExamples.isEmpty ? 3 : 4;
            final controlsWidth =
                controlCount * kMinInteractiveDimension +
                controlCount * spacing;
            final searchWidth = width < 480 || enlargedText
                ? width
                : width - controlsWidth;
            return Wrap(
              spacing: spacing,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  key: const Key('admin-queue-search-slot'),
                  width: searchWidth,
                  child: searchField(),
                ),
                statusFilter,
                sortFilter,
                if (searchExamples.isNotEmpty)
                  PopupMenuButton<AdminSearchExample>(
                    key: const Key('admin-smart-search-examples'),
                    tooltip: 'Smart search examples',
                    onSelected: (example) {
                      searchController.text = example.query;
                      onRefresh();
                    },
                    itemBuilder: (context) => [
                      for (final example in searchExamples)
                        PopupMenuItem(
                          value: example,
                          child: Text(example.label),
                        ),
                    ],
                    icon: const Icon(Icons.manage_search_rounded),
                    constraints: const BoxConstraints(minWidth: 220),
                  ),
                refreshButton,
              ],
            );
          },
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: option.value == selectedValue
                        ? const Icon(Icons.check_rounded, size: 18)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(option.label, softWrap: true)),
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
            dimension: kMinInteractiveDimension,
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

class AdminSearchExample {
  const AdminSearchExample({required this.label, required this.query});

  final String label;
  final String query;
}
