import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _GroupVisibilityFilter _visibilityFilter = _GroupVisibilityFilter.all;
  _GroupSort _sort = _GroupSort.collected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(
      collectRepositoryProvider.select((state) => state.collections),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    final query = _query.trim().toLowerCase();
    final visibleCollections = [
      for (final collection in collections)
        if (_matchesQuery(collection, query) &&
            _matchesVisibility(collection, _visibilityFilter))
          collection,
    ]..sort((left, right) => _compareGroups(left, right, summaries, _sort));
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    if (collections.isEmpty) {
      return ScreenScaffold(
        title: 'Groups',
        children: [
          EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'No groups yet',
            message: 'Create an Android owner group, or scan a group QR code.',
            action: CollectButton(
              label: 'Scan',
              icon: CollectIcons.qr,
              onPressed: () => context.go('/groups/scan'),
            ),
          ),
          if (showCreate)
            CollectButton(
              label: 'Create group',
              icon: CollectIcons.add,
              onPressed: () => context.go('/groups/create'),
              expand: true,
            ),
        ],
      );
    }
    return ScreenScaffold(
      title: 'Groups',
      actions: [
        if (showCreate)
          IconButton.filled(
            tooltip: 'New group',
            onPressed: () => context.go('/groups/create'),
            icon: const Icon(CollectIcons.add),
          ),
        IconButton(
          tooltip: 'Scan QR code',
          onPressed: () => context.go('/groups/scan'),
          icon: const Icon(CollectIcons.qr),
        ),
      ],
      children: [
        SearchWithClearField(
          controller: _search,
          label: 'Search groups',
          onChanged: (value) => setState(() => _query = value),
        ),
        _GroupControlDock(
          filterLabel: _visibilityFilterLabel(_visibilityFilter),
          sortLabel: _sortLabel(_sort),
          onFilterTap: _showFilterSheet,
          onSortTap: _showSortSheet,
        ),
        if (visibleCollections.isEmpty)
          EmptySearchState(
            title: 'No groups found',
            message: 'No group matches the current search or filter.',
            onClear: () => setState(() {
              _search.clear();
              _query = '';
              _visibilityFilter = _GroupVisibilityFilter.all;
              _sort = _GroupSort.collected;
            }),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 640 ? 2 : 1;
              const gap = CollectSpacing.x3;
              final columnWidth =
                  (constraints.maxWidth - (gap * (columns - 1))) / columns;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                itemCount: visibleCollections.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  childAspectRatio: columnWidth / 220,
                ),
                itemBuilder: (context, index) {
                  final collection = visibleCollections[index];
                  return GroupCard(
                    collection: collection,
                    summary:
                        summaries[collection.id] ??
                        const CollectionSummary(
                          amountRaisedRwf: 0,
                          supporterCount: 0,
                        ),
                    variant: GroupCardVariant.visual,
                    onTap: () => context.go('/groups/${collection.id}'),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return CollectBottomSheet(
          child: _GroupOptionSheet<_GroupSort>(
            title: 'Sort groups',
            values: _GroupSort.values,
            selected: _sort,
            labelFor: _sortLabel,
            onSelected: (sort) {
              setState(() => _sort = sort);
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return CollectBottomSheet(
          child: _GroupOptionSheet<_GroupVisibilityFilter>(
            title: 'Filter groups',
            values: _GroupVisibilityFilter.values,
            selected: _visibilityFilter,
            labelFor: _visibilityFilterLabel,
            onSelected: (filter) {
              setState(() => _visibilityFilter = filter);
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }
}

class _GroupControlDock extends StatelessWidget {
  const _GroupControlDock({
    required this.filterLabel,
    required this.sortLabel,
    required this.onFilterTap,
    required this.onSortTap,
  });

  final String filterLabel;
  final String sortLabel;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _GroupControlButton(
            icon: CollectIcons.public,
            title: 'Visibility',
            value: filterLabel,
            onTap: onFilterTap,
          ),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: _GroupControlButton(
            icon: CollectIcons.activity,
            title: 'Sort',
            value: sortLabel,
            onTap: onSortTap,
          ),
        ),
      ],
    );
  }
}

class _GroupControlButton extends StatelessWidget {
  const _GroupControlButton({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      label: '$title $value',
      child: Material(
        color: colors.surfaceRaised.withValues(alpha: 0.92),
        borderRadius: CollectRadius.pillBorder,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(color: colors.border.withValues(alpha: 0.76)),
          ),
          child: InkWell(
            borderRadius: CollectRadius.pillBorder,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x3,
                vertical: CollectSpacing.x2,
              ),
              child: Row(
                children: [
                  Icon(icon, color: colors.actionCrimson, size: 20),
                  CollectSpacing.gapW8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: CollectTypography.eyebrowLabel(
                            colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(CollectIcons.chevron, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupOptionSheet<T> extends StatelessWidget {
  const _GroupOptionSheet({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          CollectSpacing.gap12,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              for (final value in values)
                _GroupSheetPill<T>(
                  value: value,
                  label: labelFor(value),
                  selected: selected == value,
                  onSelected: onSelected,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupSheetPill<T> extends StatelessWidget {
  const _GroupSheetPill({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final T value;
  final String label;
  final bool selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Material(
      color: selected ? colors.actionCrimson : colors.surface,
      borderRadius: CollectRadius.pillBorder,
      child: InkWell(
        borderRadius: CollectRadius.pillBorder,
        onTap: () => onSelected(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x3,
            vertical: CollectSpacing.x2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? CollectIcons.check : CollectIcons.filter,
                size: 18,
                color: selected ? Colors.white : colors.textSecondary,
              ),
              CollectSpacing.gapW8,
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GroupVisibilityFilter { all, public, private }

enum _GroupSort { recent, collected, members }

bool _matchesQuery(CollectCollection collection, String query) {
  if (query.isEmpty) return true;
  return collection.title.toLowerCase().contains(query) ||
      collection.slug.toLowerCase().contains(query);
}

bool _matchesVisibility(
  CollectCollection collection,
  _GroupVisibilityFilter filter,
) {
  return switch (filter) {
    _GroupVisibilityFilter.all => true,
    _GroupVisibilityFilter.public => collection.isPublic,
    _GroupVisibilityFilter.private => !collection.isPublic,
  };
}

int _compareGroups(
  CollectCollection left,
  CollectCollection right,
  Map<String, CollectionSummary> summaries,
  _GroupSort sort,
) {
  final leftSummary =
      summaries[left.id] ??
      const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
  final rightSummary =
      summaries[right.id] ??
      const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
  final result = switch (sort) {
    _GroupSort.recent => right.createdAt.compareTo(left.createdAt),
    _GroupSort.collected => rightSummary.amountRaisedRwf.compareTo(
      leftSummary.amountRaisedRwf,
    ),
    _GroupSort.members => rightSummary.supporterCount.compareTo(
      leftSummary.supporterCount,
    ),
  };
  if (result != 0) return result;
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}

String _visibilityFilterLabel(_GroupVisibilityFilter filter) {
  return switch (filter) {
    _GroupVisibilityFilter.all => 'All',
    _GroupVisibilityFilter.public => 'Public',
    _GroupVisibilityFilter.private => 'Private',
  };
}

String _sortLabel(_GroupSort sort) {
  return switch (sort) {
    _GroupSort.recent => 'Recent',
    _GroupSort.collected => 'Collected',
    _GroupSort.members => 'Members',
  };
}
