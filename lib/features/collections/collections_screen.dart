import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_data_load_failure.dart';
import '../../shared/widgets/collect_group_cards.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final collections = ref.watch(activeCollectionsProvider);
    final isInitialLoading =
        state.isLoading &&
        collections.isEmpty &&
        state.contributions.isEmpty &&
        state.paymentIntents.isEmpty;
    final summaries = ref.watch(collectionSummariesProvider);
    final contributedCollectionIds = ref.watch(
      contributedCollectionIdsProvider,
    );
    final routeUri = _maybeRouteUri(context);
    final showContributedOnly =
        routeUri.queryParameters['filter'] == 'contributed';
    final query = _query.trim().toLowerCase();
    final visibleCollections = [
      for (final collection in collections)
        if (!showContributedOnly ||
            contributedCollectionIds.contains(collection.id))
          if (query.isEmpty || _matchesQuery(collection, query)) collection,
    ]..sort((left, right) => _compareGroups(left, right, summaries));
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    final pageTitle = showContributedOnly ? 'My groups' : 'Groups';
    if (isInitialLoading) {
      return ScreenScaffold(
        title: 'Groups',
        showHeader: false,
        compact: true,
        topChrome: CollectScreenTopChrome(
          searchLabel: 'Search groups',
          onAvatarTap: () => context.go('/settings'),
          onSearchTap: _beginSearch,
        ),
        onRefresh: () =>
            ref.read(collectRepositoryProvider.notifier).loadInitial(),
        children: const [
          CollectScreenLoadingState(
            title: 'Loading groups',
            message: 'Refreshing group cards, balances, and filters.',
            icon: CollectIcons.collections,
            skeletonCount: 3,
          ),
        ],
      );
    }
    if (collections.isEmpty) {
      return ScreenScaffold(
        title: 'Groups',
        showHeader: false,
        compact: true,
        topChrome: CollectScreenTopChrome(
          searchLabel: 'Search groups',
          onAvatarTap: () => context.go('/settings'),
          onSearchTap: _beginSearch,
          actions: [
            if (showCreate)
              CollectChromeAction(
                icon: CollectIcons.add,
                tooltip: 'Create group',
                onPressed: () => context.go('/groups/create'),
              ),
          ],
        ),
        onRefresh: () =>
            ref.read(collectRepositoryProvider.notifier).loadInitial(),
        children: [
          if (_searching)
            SearchWithClearField(
              controller: _search,
              focusNode: _searchFocus,
              label: 'Search group name, type, or purpose',
              onChanged: (value) => setState(() => _query = value),
            ),
          if (state.hasInitialLoadFailure)
            CollectDataLoadFailure(
              onRetry: () =>
                  ref.read(collectRepositoryProvider.notifier).loadInitial(),
            )
          else
            const EmptyIllustrationState(
              icon: CollectIcons.collections,
              title: 'No groups yet',
              message: 'Create a group or scan a group QR to start collecting.',
            ),
        ],
      );
    }
    return ScreenScaffold(
      title: 'Groups',
      showHeader: false,
      compact: true,
      topChrome: CollectScreenTopChrome(
        searchLabel: 'Search groups',
        onAvatarTap: () => context.go('/settings'),
        onSearchTap: _beginSearch,
        actions: [
          if (showCreate)
            CollectChromeAction(
              icon: CollectIcons.add,
              tooltip: 'Create group',
              onPressed: () => context.go('/groups/create'),
            ),
          CollectChromeAction(
            icon: CollectIcons.filter,
            tooltip: showContributedOnly ? 'Show all groups' : 'My groups',
            onPressed: () => context.go(
              showContributedOnly ? '/groups' : '/groups?filter=contributed',
            ),
          ),
        ],
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: [
        SectionHeader(title: pageTitle),
        if (_searching)
          SearchWithClearField(
            controller: _search,
            focusNode: _searchFocus,
            label: 'Search group name, type, or purpose',
            onChanged: (value) => setState(() => _query = value),
          ),
        if (visibleCollections.isNotEmpty)
          _GroupsCardGrid(collections: visibleCollections, summaries: summaries)
        else if (query.isNotEmpty)
          EmptySearchState(
            title: 'No matching groups',
            message: 'Clear the search and try again.',
            onClear: _clearSearch,
          )
        else if (showContributedOnly)
          EmptySearchState(
            title: 'No groups yet',
            message:
                'Confirmed contributions will place active groups in this view.',
            onClear: () => context.go('/groups'),
            clearLabel: 'Show all groups',
          )
        else
          const EmptyIllustrationState(
            icon: CollectIcons.collections,
            title: 'No groups yet',
            message: 'Create a group or scan a group QR to start collecting.',
          ),
      ],
    );
  }

  bool _matchesQuery(CollectCollection collection, String query) {
    return collection.title.toLowerCase().contains(query) ||
        collection.description.toLowerCase().contains(query) ||
        collection.collectionType.name.toLowerCase().contains(query) ||
        (collection.purposeLabel?.toLowerCase().contains(query) ?? false);
  }

  void _beginSearch() {
    if (!_searching) setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _clearSearch() {
    setState(() {
      _search.clear();
      _query = '';
    });
  }
}

class _GroupsCardGrid extends StatelessWidget {
  const _GroupsCardGrid({required this.collections, required this.summaries});

  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 2 : 1;
        const gap = CollectSpacing.x3;
        final columnWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          clipBehavior: Clip.none,
          itemCount: collections.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: columnWidth / 220,
          ),
          itemBuilder: (context, index) {
            final collection = collections[index];
            return GroupCard(
              collection: collection,
              summary:
                  summaries[collection.id] ??
                  const CollectionSummary(
                    amountRaisedRwf: 0,
                    supporterCount: 0,
                  ),
              variant: GroupCardVariant.publicDiscovery,
              onTap: () => context.go('/groups/${collection.id}'),
              primaryAction: collection.isPublic
                  ? _GroupsContributeIconButton(
                      groupTitle: collection.title,
                      onPressed: () =>
                          context.go('/groups/${collection.id}/contribute'),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

class _GroupsContributeIconButton extends StatelessWidget {
  const _GroupsContributeIconButton({
    required this.groupTitle,
    required this.onPressed,
  });

  final String groupTitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return IconButton.filledTonal(
      tooltip: 'Contribute to $groupTitle',
      style: IconButton.styleFrom(
        backgroundColor: colors.textPrimary.withValues(alpha: 0.10),
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.textPrimary.withValues(alpha: 0.14)),
        fixedSize: const Size.square(CollectSpacing.iconTarget),
        minimumSize: const Size.square(CollectSpacing.iconTarget),
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      icon: const Icon(CollectIcons.donate),
    );
  }
}

Uri _maybeRouteUri(BuildContext context) {
  try {
    return GoRouterState.of(context).uri;
  } on Object {
    return Uri(path: '/groups');
  }
}

int _compareGroups(
  CollectCollection left,
  CollectCollection right,
  Map<String, CollectionSummary> summaries,
) {
  final leftSummary =
      summaries[left.id] ??
      const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
  final rightSummary =
      summaries[right.id] ??
      const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0);
  // Compare amounts only when both groups settle in the same single currency.
  // Mixed-currency groups have no meaningful global monetary ranking.
  final leftTotals = leftSummary.totalsByCurrency;
  final rightTotals = rightSummary.totalsByCurrency;
  final leftKey = (leftTotals.keys.toList()..sort()).join(',');
  final rightKey = (rightTotals.keys.toList()..sort()).join(',');
  final currencyOrder = leftKey.compareTo(rightKey);
  if (currencyOrder != 0) return currencyOrder;
  if (leftTotals.length == 1 && rightTotals.length == 1) {
    final result = rightTotals.values.single.compareTo(
      leftTotals.values.single,
    );
    if (result != 0) return result;
  }
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
