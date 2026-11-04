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
    final supportedGroupsUnknown =
        showContributedOnly && state.historyPage == null;
    final showMembersOnly = routeUri.queryParameters['filter'] == 'member';
    final showFeaturedOnly = routeUri.queryParameters['filter'] == 'featured';
    final includesPublicDiscovery = !showMembersOnly && !showContributedOnly;
    final publicDiscoveryLoading =
        includesPublicDiscovery &&
        (state.isLoading || state.publicDiscoveryLoading);
    final publicDiscoveryUnavailable =
        includesPublicDiscovery &&
        !publicDiscoveryLoading &&
        state.publicDiscoveryUnavailable;
    final publicDiscoveryUncertain =
        includesPublicDiscovery &&
        !publicDiscoveryLoading &&
        !publicDiscoveryUnavailable &&
        (state.usingStaleCache ||
            state.financialObservationUncertain ||
            state.lastSuccessfulSyncAt == null);
    final publicResultsUnconfirmed =
        state.lastSuccessfulSyncAt == null &&
        !state.usingStaleCache &&
        !state.financialObservationUncertain;
    Widget publicResultsUncertain() => Semantics(
      liveRegion: true,
      child: MinimalStatePanel(
        icon: CollectIcons.sync,
        title: publicResultsUnconfirmed
            ? 'Public groups not yet confirmed'
            : 'Public groups may be incomplete',
        message: publicResultsUnconfirmed
            ? 'Group information has not been confirmed yet.'
            : 'Loaded groups may be out of date.',
        tone: CollectStatusTone.warning,
        primaryAction: publicResultsUnconfirmed && !publicDiscoveryUnavailable
            ? null
            : CollectButton(
                label: publicDiscoveryUnavailable ? 'Retry' : 'Refresh groups',
                icon: CollectIcons.sync,
                onPressed: () =>
                    ref.read(collectRepositoryProvider.notifier).loadInitial(),
                expand: true,
              ),
      ),
    );
    Widget supportedGroupsUnavailable() => MinimalStatePanel(
      icon: CollectIcons.collections,
      title: 'Supported groups unavailable',
      message:
          'Connect and refresh to load the complete list of groups you have supported.',
      tone: CollectStatusTone.warning,
      primaryAction: CollectButton(
        label: 'Refresh groups',
        onPressed: () =>
            ref.read(collectRepositoryProvider.notifier).loadInitial(),
      ),
    );
    final memberCollectionIds = ref
        .watch(memberCollectionsProvider)
        .map((collection) => collection.id)
        .toSet();
    final query = _query.trim().toLowerCase();
    final visibleCollections = [
      for (final collection in collections)
        if (!showFeaturedOnly || collection.isPublic)
          if (!showMembersOnly || memberCollectionIds.contains(collection.id))
            if (!showContributedOnly ||
                contributedCollectionIds.contains(collection.id))
              if (query.isEmpty || _matchesQuery(collection, query)) collection,
    ]..sort((left, right) => _compareGroups(left, right, summaries));
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    final pageTitle = showFeaturedOnly
        ? 'Featured Groups'
        : showMembersOnly
        ? 'My groups'
        : showContributedOnly
        ? 'Supported groups'
        : 'Groups';
    if (isInitialLoading || (collections.isEmpty && publicDiscoveryLoading)) {
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
          if (publicDiscoveryUnavailable && state.usingStaleCache)
            publicResultsUncertain()
          else if (state.hasInitialLoadFailure || publicDiscoveryUnavailable)
            CollectDataLoadFailure(
              onRetry: () =>
                  ref.read(collectRepositoryProvider.notifier).loadInitial(),
            )
          else if (supportedGroupsUnknown)
            supportedGroupsUnavailable()
          else if (publicDiscoveryUncertain)
            publicResultsUncertain()
          else
            EmptyIllustrationState(
              icon: CollectIcons.collections,
              title: showFeaturedOnly
                  ? 'No featured groups loaded'
                  : 'No groups loaded',
              message: showMembersOnly
                  ? 'Groups you create or join will appear here.'
                  : showContributedOnly
                  ? 'Recorded contributions will place active groups in this view.'
                  : 'Groups will appear here as they are loaded.',
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
            tooltip: showMembersOnly || showContributedOnly || showFeaturedOnly
                ? 'Show all groups'
                : 'My groups',
            onPressed: () => context.go(
              showMembersOnly || showContributedOnly || showFeaturedOnly
                  ? '/groups'
                  : '/groups?filter=member',
            ),
          ),
        ],
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: [
        SectionHeader(title: pageTitle),
        if (publicDiscoveryUnavailable && state.usingStaleCache)
          publicResultsUncertain()
        else if (publicDiscoveryUnavailable)
          CollectDataLoadFailure(
            onRetry: () =>
                ref.read(collectRepositoryProvider.notifier).loadInitial(),
          )
        else if (publicDiscoveryUncertain)
          publicResultsUncertain(),
        if (_searching)
          SearchWithClearField(
            controller: _search,
            focusNode: _searchFocus,
            label: 'Search group name, type, or purpose',
            onChanged: (value) => setState(() => _query = value),
          ),
        if (publicDiscoveryLoading)
          const CollectScreenLoadingState(
            title: 'Loading public groups',
            message: 'Public groups are still being refreshed.',
            icon: CollectIcons.collections,
            skeletonCount: 1,
          ),
        if (supportedGroupsUnknown) supportedGroupsUnavailable(),
        if (visibleCollections.isNotEmpty)
          _GroupsCardGrid(collections: visibleCollections, summaries: summaries)
        else if (supportedGroupsUnknown ||
            publicDiscoveryLoading ||
            publicDiscoveryUnavailable ||
            publicDiscoveryUncertain)
          const SizedBox.shrink()
        else if (query.isNotEmpty)
          EmptySearchState(
            title: 'No matches in loaded groups',
            message: 'Only loaded groups were searched.',
            onClear: _clearSearch,
          )
        else if (showFeaturedOnly)
          const EmptyIllustrationState(
            icon: CollectIcons.people,
            title: 'No featured groups loaded',
            message: 'Featured public groups will appear here as they load.',
          )
        else if (showMembersOnly || showContributedOnly)
          EmptySearchState(
            title: 'No groups yet',
            message: showMembersOnly
                ? 'Groups you create or join will appear here.'
                : 'Recorded contributions will place active groups in this view.',
            onClear: () => context.go('/groups'),
            clearLabel: 'Show all groups',
          )
        else
          const EmptyIllustrationState(
            icon: CollectIcons.collections,
            title: 'No groups yet',
            message:
                'Explore public groups or create a group to start collecting.',
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
    return GroupCardLayout(
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final collection = collections[index];
        return GroupCard(
          collection: collection,
          summary: summaries[collection.id],
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
    return GroupCardActionButton(
      tooltip: 'Contribute to $groupTitle',
      onPressed: onPressed,
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
  final leftSummary = summaries[left.id];
  final rightSummary = summaries[right.id];
  // A missing aggregate is unknown, never a measured zero. Keep groups with
  // supplied totals ahead of groups whose totals cannot be ranked.
  if (leftSummary == null) {
    return rightSummary == null
        ? left.title.toLowerCase().compareTo(right.title.toLowerCase())
        : 1;
  }
  if (rightSummary == null) return -1;
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
