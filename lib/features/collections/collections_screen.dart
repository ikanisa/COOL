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
        Row(
          children: [
            Expanded(
              child: _GroupFilterRail(
                selected: _visibilityFilter,
                onChanged: (value) => setState(() => _visibilityFilter = value),
              ),
            ),
            CollectSpacing.gapW8,
            _GroupSortButton(label: _sortLabel(_sort), onTap: _showSortSheet),
          ],
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
      builder: (context) {
        return CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sort groups',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              CollectSpacing.gap12,
              for (final sort in _GroupSort.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _sort == sort ? CollectIcons.check : CollectIcons.filter,
                  ),
                  title: Text(_sortLabel(sort)),
                  onTap: () {
                    setState(() => _sort = sort);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupFilterRail extends StatelessWidget {
  const _GroupFilterRail({required this.selected, required this.onChanged});

  final _GroupVisibilityFilter selected;
  final ValueChanged<_GroupVisibilityFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: _GroupVisibilityFilter.values.length,
        separatorBuilder: (_, _) => CollectSpacing.gapW8,
        itemBuilder: (context, index) {
          final filter = _GroupVisibilityFilter.values[index];
          return _GroupFilterPill(
            label: _visibilityFilterLabel(filter),
            selected: selected == filter,
            onTap: () => onChanged(filter),
          );
        },
      ),
    );
  }
}

class _GroupFilterPill extends StatelessWidget {
  const _GroupFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.actionCrimson : colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x4,
              vertical: CollectSpacing.x2,
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupSortButton extends StatelessWidget {
  const _GroupSortButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Tooltip(
      message: 'Sort groups',
      child: Material(
        color: colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x3,
              vertical: CollectSpacing.x2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CollectIcons.filter, size: 18),
                CollectSpacing.gapW8,
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
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
