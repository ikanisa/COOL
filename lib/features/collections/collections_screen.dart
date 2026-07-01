import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
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
    final collections = state.collections;
    final isInitialLoading =
        state.isLoading &&
        state.collections.isEmpty &&
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
        onRefresh: () =>
            ref.read(collectRepositoryProvider.notifier).loadInitial(),
        children: [
          _GroupEmptyActionRail(
            showCreate: showCreate,
            onScan: () => context.go('/groups/scan'),
            onCreate: () => context.go('/groups/create'),
          ),
        ],
      );
    }
    return ScreenScaffold(
      title: 'Groups',
      showHeader: false,
      compact: true,
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: [
        SectionHeader(title: pageTitle),
        _GroupsMomentumPanel(
          collections: visibleCollections,
          summaries: summaries,
          showContributedOnly: showContributedOnly,
        ),
        if (visibleCollections.isNotEmpty)
          _GroupsCardGrid(collections: visibleCollections, summaries: summaries)
        else if (!showContributedOnly)
          _GroupEmptyActionRail(
            showCreate: showCreate,
            onScan: () => context.go('/groups/scan'),
            onCreate: () => context.go('/groups/create'),
          ),
      ],
    );
  }
}

class _GroupsMomentumPanel extends StatelessWidget {
  const _GroupsMomentumPanel({
    required this.collections,
    required this.summaries,
    required this.showContributedOnly,
  });

  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;
  final bool showContributedOnly;

  @override
  Widget build(BuildContext context) {
    final totalRaised = collections.fold<int>(
      0,
      (total, collection) =>
          total + (summaries[collection.id]?.amountRaisedRwf ?? 0),
    );
    final members = collections.fold<int>(
      0,
      (total, collection) =>
          total + (summaries[collection.id]?.supporterCount ?? 0),
    );
    final publicCount = collections
        .where((collection) => collection.isPublic)
        .length;
    return Semantics(
      container: true,
      label:
          'Total collected ${formatRwf(totalRaised)}, ${collections.length} groups, $members members, $publicCount public groups',
      child: CollectCard(
        emphasis: CollectCardEmphasis.glow,
        padding: const EdgeInsets.all(CollectSpacing.x4),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CollectToneIcon(
                    icon: showContributedOnly
                        ? CollectIcons.check
                        : CollectIcons.collections,
                    tone: CollectStatusTone.success,
                  ),
                  CollectSpacing.gapW12,
                  Expanded(
                    child: Text(
                      showContributedOnly
                          ? 'Supported activity'
                          : 'Group activity',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              CollectSpacing.gap16,
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRwf(totalRaised),
                  style: CollectTypography.amountLarge(
                    context.collectColors.textPrimary,
                  ).copyWith(height: 0.98),
                ),
              ),
              CollectSpacing.gap16,
              Row(
                children: [
                  Expanded(
                    child: _GroupsMetricPill(
                      icon: CollectIcons.collections,
                      label: showContributedOnly ? 'Supported' : 'Groups',
                      value: '${collections.length}',
                    ),
                  ),
                  CollectSpacing.gapW8,
                  Expanded(
                    child: _GroupsMetricPill(
                      icon: CollectIcons.people,
                      label: 'Members',
                      value: '$members',
                    ),
                  ),
                  CollectSpacing.gapW8,
                  Expanded(
                    child: _GroupsMetricPill(
                      icon: CollectIcons.public,
                      label: 'Public',
                      value: '$publicCount',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupsMetricPill extends StatelessWidget {
  const _GroupsMetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.07),
        borderRadius: CollectRadius.mdBorder,
        border: Border.all(color: colors.textPrimary.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x2,
          vertical: CollectSpacing.x2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.textSecondary, size: 17),
            CollectSpacing.gap4,
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
          return Column(
            children: [
              for (var index = 0; index < collections.length; index += 1)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == collections.length - 1
                        ? 0
                        : CollectSpacing.x3,
                  ),
                  child: GroupCard(
                    collection: collections[index],
                    summary:
                        summaries[collections[index].id] ??
                        const CollectionSummary(
                          amountRaisedRwf: 0,
                          supporterCount: 0,
                        ),
                    variant: GroupCardVariant.compact,
                    onTap: () => context.go('/groups/${collections[index].id}'),
                  ),
                ),
            ],
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

class _GroupEmptyActionRail extends StatelessWidget {
  const _GroupEmptyActionRail({
    required this.showCreate,
    required this.onScan,
    required this.onCreate,
  });

  final bool showCreate;
  final VoidCallback onScan;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _GroupEmptyActionItem(
        icon: CollectIcons.qr,
        label: 'Scan',
        onTap: onScan,
      ),
      if (showCreate)
        _GroupEmptyActionItem(
          icon: CollectIcons.add,
          label: 'Create group',
          onTap: onCreate,
        ),
    ];

    return SizedBox(
      height: 78,
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: actions[index]),
            if (index != actions.length - 1) CollectSpacing.gapW12,
          ],
        ],
      ),
    );
  }
}

class _GroupEmptyActionItem extends StatelessWidget {
  const _GroupEmptyActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final iconFill = isDark
        ? CollectColors.inkPrimary.withValues(alpha: 0.92)
        : colors.textPrimary.withValues(alpha: 0.88);
    final iconBorder = foreground.withValues(alpha: isDark ? 0.22 : 0.20);

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: iconFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: iconBorder),
                ),
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(icon, color: foreground, size: 23),
                ),
              ),
              CollectSpacing.gap4,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
