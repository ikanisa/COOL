import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_group_cards.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
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
    final visibleCollections = [
      for (final collection in collections)
        if (!showContributedOnly ||
            contributedCollectionIds.contains(collection.id))
          collection,
    ]..sort((left, right) => _compareGroups(left, right, summaries));
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    final pageTitle = showContributedOnly ? 'Supported groups' : 'Groups';
    if (isInitialLoading) {
      return ScreenScaffold(
        title: 'Groups',
        showHeader: false,
        compact: true,
        topChrome: CollectScreenTopChrome(
          searchLabel: 'Search groups',
          onAvatarTap: () => context.go('/settings'),
          onSearchTap: () => context.go('/groups'),
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
          onSearchTap: () => context.go('/groups'),
          actions: [
            if (showCreate)
              CollectChromeAction(
                icon: CollectIcons.add,
                tooltip: 'Create group',
                onPressed: () => context.go('/groups/create'),
              ),
          ],
        ),
        hero: const CollectScreenHero(
          eyebrow: 'GROUPS',
          title: 'Start collecting',
          metric: '0',
          subtitle: 'Create a group or scan a group QR',
          icon: CollectIcons.collections,
        ),
        onRefresh: () =>
            ref.read(collectRepositoryProvider.notifier).loadInitial(),
        children: const [
          EmptyIllustrationState(
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
        onSearchTap: () => context.go('/groups'),
        actions: [
          if (showCreate)
            CollectChromeAction(
              icon: CollectIcons.add,
              tooltip: 'Create group',
              onPressed: () => context.go('/groups/create'),
            ),
          CollectChromeAction(
            icon: CollectIcons.filter,
            tooltip: showContributedOnly ? 'Show all groups' : 'Supported',
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
        if (visibleCollections.isNotEmpty)
          _GroupsCardGrid(collections: visibleCollections, summaries: summaries)
        else if (showContributedOnly)
          EmptySearchState(
            title: 'No supported groups yet',
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
}

class _GroupsCardGrid extends StatelessWidget {
  const _GroupsCardGrid({required this.collections, required this.summaries});

  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return GroupListPanel(
            collections: collections,
            summaries: summaries,
            onGroupTap: (collection) => context.go('/groups/${collection.id}'),
          );
        }
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
              variant: GroupCardVariant.compact,
              onTap: () => context.go('/groups/${collection.id}'),
            );
          },
        );
      },
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
  final result = rightSummary.amountRaisedRwf.compareTo(
    leftSummary.amountRaisedRwf,
  );
  if (result != 0) return result;
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
