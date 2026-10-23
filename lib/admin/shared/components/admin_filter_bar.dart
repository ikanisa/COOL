import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_radius.dart';

class AdminFilterBar extends StatefulWidget {
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
  State<AdminFilterBar> createState() => _AdminFilterBarState();
}

class _AdminFilterBarState extends State<AdminFilterBar> {
  final FocusNode _searchFocusNode = FocusNode(
    debugLabel: 'Admin queue search',
  );

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    Widget searchField() => ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.searchController,
      builder: (context, value, _) => Stack(
        children: [
          Semantics(
            label: widget.searchLabel,
            hint: 'Searches all matching records. Press Enter or Apply search.',
            child: TextField(
              key: const Key('admin-queue-search-input'),
              controller: widget.searchController,
              focusNode: _searchFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => widget.onRefresh(),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 28),
                // Independent actions avoid InputDecorator's offscreen suffix
                // semantics clipping while retaining the full-width field/focus ring.
                contentPadding: EdgeInsetsDirectional.fromSTEB(
                  16,
                  12,
                  (value.text.isEmpty ? 1 : 2) * kMinInteractiveDimension + 16,
                  12,
                ),
                filled: true,
                fillColor: colors.surfaceRaised.withValues(alpha: 0.48),
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
          Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.text.isNotEmpty)
                    Tooltip(
                      message: 'Clear search',
                      excludeFromSemantics: true,
                      child: IconButton(
                        key: const Key('admin-queue-clear-search'),
                        constraints: const BoxConstraints.tightFor(
                          width: kMinInteractiveDimension,
                          height: kMinInteractiveDimension,
                        ),
                        onPressed: () {
                          widget.searchController.clear();
                          // Reconnect text input with the cleared controller value.
                          _searchFocusNode.requestFocus();
                          widget.onRefresh();
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 28,
                          semanticLabel: 'Clear search',
                        ),
                      ),
                    ),
                  Tooltip(
                    message: 'Apply search',
                    excludeFromSemantics: true,
                    child: IconButton(
                      key: const Key('admin-queue-apply-search'),
                      constraints: const BoxConstraints.tightFor(
                        width: kMinInteractiveDimension,
                        height: kMinInteractiveDimension,
                      ),
                      onPressed: widget.onRefresh,
                      icon: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 28,
                        semanticLabel: 'Apply search',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    String selectedLabel(List<AdminFilterOption> options, String value) {
      for (final option in options) {
        if (option.value == value) return option.label;
      }
      return '';
    }

    final statusLabel = selectedLabel(widget.statusOptions, widget.status);
    final sortLabel = selectedLabel(widget.sortOptions, widget.sortBy);
    final statusFilter = _AdminFilterMenu(
      key: const Key('admin-status-filter-select'),
      tooltip: 'Filter: ${statusLabel.isEmpty ? 'All' : statusLabel}',
      semanticLabel:
          'Status filter, ${statusLabel.isEmpty ? 'All' : statusLabel} selected',
      icon: widget.status.isEmpty
          ? Icons.filter_alt_outlined
          : Icons.filter_alt_rounded,
      selectedValue: widget.status,
      options: widget.statusOptions,
      onSelected: widget.onStatusChanged,
    );
    final sortFilter = _AdminFilterMenu(
      key: const Key('admin-sort-filter-select'),
      tooltip: 'Sort: ${sortLabel.isEmpty ? 'Newest' : sortLabel}',
      semanticLabel:
          'Sort order, ${sortLabel.isEmpty ? 'Newest' : sortLabel} selected',
      icon: Icons.sort_rounded,
      selectedValue: widget.sortBy,
      options: widget.sortOptions,
      onSelected: widget.onSortChanged,
    );

    final refreshButton = IconButton(
      key: const Key('admin-queue-refresh'),
      constraints: const BoxConstraints.tightFor(
        width: kMinInteractiveDimension,
        height: kMinInteractiveDimension,
      ),
      tooltip: 'Refresh',
      onPressed: widget.onRefresh,
      icon: const Icon(Icons.refresh, size: 28),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure at the actual input font size, not scale(1), so nonlinear
        // text scaling also gets a full-width search field when needed.
        final fontSize =
            Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16.0;
        final enlargedText =
            MediaQuery.textScalerOf(context).scale(fontSize) > fontSize * 1.3;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        const spacing = 4.0;
        final controlCount = widget.searchExamples.isEmpty ? 3 : 4;
        final controlsWidth =
            controlCount * kMinInteractiveDimension + controlCount * spacing;
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
            if (widget.searchExamples.isNotEmpty)
              PopupMenuButton<AdminSearchExample>(
                key: const Key('admin-smart-search-examples'),
                tooltip: 'Smart search examples',
                onSelected: (example) {
                  widget.searchController.text = example.query;
                  widget.onRefresh();
                },
                itemBuilder: (context) => [
                  for (final example in widget.searchExamples)
                    PopupMenuItem(value: example, child: Text(example.label)),
                ],
                icon: const Icon(Icons.manage_search_rounded, size: 28),
                constraints: const BoxConstraints(minWidth: 220),
              ),
            refreshButton,
          ],
        );
      },
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
        child: SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Icon(icon, size: 28, color: colors.textPrimary),
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
