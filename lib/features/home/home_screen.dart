import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_creation_platform.dart';
import '../collections/group_share_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(homeCollectionsProvider);
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    final paymentIntents = ref.watch(
      collectRepositoryProvider.select((state) => state.paymentIntents),
    );
    final collectionCount = ref.watch(
      collectRepositoryProvider.select((state) => state.collections.length),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    final raisedTotal = ref.watch(raisedTotalProvider);
    final contributions = ref.watch(
      collectRepositoryProvider.select((state) => state.contributions),
    );
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    return ScreenScaffold(
      title: 'Home',
      showHeader: false,
      compact: true,
      persistentPill: CollectTopChrome(
        avatarLabel: profile?.publicId,
        searchLabel: 'Search groups',
        onSearchTap: () => context.go('/groups'),
        onAvatarTap: () => context.go('/settings/profile'),
        hasUnread: paymentIntents.isNotEmpty,
        actions: [
          CollectTopChromeAction(
            icon: CollectIcons.pending,
            tooltip: 'Notifications',
            hasBadge: paymentIntents.isNotEmpty,
            onPressed: () => context.go('/notifications'),
          ),
          CollectTopChromeAction(
            icon: CollectIcons.profile,
            tooltip: 'Profile',
            onPressed: () => context.go('/settings/profile'),
          ),
        ],
      ),
      children: [
        _HomeTotalCollectedCard(
          totalAmount: raisedTotal,
          collectionCount: collectionCount,
          publicId: profile?.publicId,
        ),
        _HomeActionStrip(
          primaryCollection: collections.isEmpty ? null : collections.first,
          showCreate: showCreate,
          onCreate: () => context.go('/groups/create'),
        ),
        _PublicGroupsSection(collections: collections, summaries: summaries),
        const SectionHeader(title: 'My groups'),
        if (collections.isEmpty)
          EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'No groups yet',
            message: 'Create a group or scan a group QR.',
            action: showCreate
                ? CollectButton(
                    label: 'Create group',
                    icon: CollectIcons.add,
                    onPressed: () => context.go('/groups/create'),
                  )
                : CollectButton(
                    label: 'Join group',
                    icon: CollectIcons.qr,
                    onPressed: () => context.go('/groups/scan'),
                  ),
          )
        else
          for (final collection in collections)
            GroupCard(
              collection: collection,
              summary:
                  summaries[collection.id] ??
                  const CollectionSummary(
                    amountRaisedRwf: 0,
                    supporterCount: 0,
                  ),
              onTap: () => context.go('/groups/${collection.id}'),
              variant: GroupCardVariant.visual,
              primaryAction: IconButton.filled(
                tooltip: 'Contribute',
                style: IconButton.styleFrom(
                  foregroundColor: context.collectColors.onImagePrimary,
                ),
                onPressed: () =>
                    context.go('/groups/${collection.id}/contribute'),
                icon: const Icon(CollectIcons.donate),
              ),
            ),
        const SectionHeader(title: 'Activity'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message:
                'Confirmed MoMo contributions will appear here after SMS verification.',
          )
        else
          CollectCard(
            child: Column(
              children: [
                for (final contribution in contributions.take(5))
                  ActivityFeedItem(
                    title: compactCollectIdLabel(contribution.supporterLabel),
                    amount: contribution.amountRwf,
                    meta: formatCollectDateTime(contribution.createdAt),
                    onTap: () => context.go(
                      '/groups/${contribution.collectionId}/ledger',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HomeTotalCollectedCard extends StatelessWidget {
  const _HomeTotalCollectedCard({
    required this.totalAmount,
    required this.collectionCount,
    this.publicId,
  });

  final int totalAmount;
  final int collectionCount;
  final String? publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [colors.actionColor, colors.periwinklePaint],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadowPaint.withValues(alpha: 0.24),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CollectBrandMark(
                compact: true,
                framed: false,
                width: 104,
                height: 30,
              ),
              if (publicId != null) ...[
                CollectSpacing.gap8,
                Text(
                  publicId!,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              CollectSpacing.gap16,
              Text(
                'TOTAL COLLECTED',
                style: CollectTypography.eyebrowLabel(colors.textPrimary),
              ),
              CollectSpacing.gap12,
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRwf(totalAmount),
                  style: CollectTypography.amountDisplay(colors.textPrimary),
                ),
              ),
              CollectSpacing.gap4,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CollectIcons.collections,
                    color: colors.textPrimary,
                    size: 20,
                  ),
                  CollectSpacing.gapW8,
                  Text(
                    collectionCount == 1
                        ? '1 group'
                        : '$collectionCount groups',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
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

class _PublicGroupsSection extends StatelessWidget {
  const _PublicGroupsSection({
    required this.collections,
    required this.summaries,
  });

  final List<CollectCollection> collections;
  final Map<String, CollectionSummary> summaries;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) {
      return const EmptyIllustrationState(
        icon: CollectIcons.collectionsOutline,
        title: 'No public groups yet',
        message: 'Groups that are safe to share will appear here.',
      );
    }

    final publicGroups = collections.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Public groups',
          actionLabel: 'View all',
          onAction: () => context.go('/groups'),
        ),
        CollectSpacing.gap12,
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            if (wide) {
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: publicGroups.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: CollectSpacing.x3,
                  crossAxisSpacing: CollectSpacing.x3,
                  childAspectRatio: 1.24,
                ),
                itemBuilder: (context, index) {
                  final collection = publicGroups[index];
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
                    primaryAction: IconButton.filled(
                      tooltip: 'Contribute',
                      style: IconButton.styleFrom(
                        foregroundColor: context.collectColors.onImagePrimary,
                        fixedSize: const Size(42, 42),
                        minimumSize: const Size(42, 42),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () =>
                          context.go('/groups/${collection.id}/contribute'),
                      icon: const Icon(CollectIcons.donate),
                    ),
                  );
                },
              );
            }
            return SizedBox(
              height: 204,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.zero,
                itemCount: publicGroups.length,
                separatorBuilder: (_, _) => CollectSpacing.gapW12,
                itemBuilder: (context, index) {
                  final collection = publicGroups[index];
                  return SizedBox(
                    width: 274,
                    child: GroupCard(
                      collection: collection,
                      summary:
                          summaries[collection.id] ??
                          const CollectionSummary(
                            amountRaisedRwf: 0,
                            supporterCount: 0,
                          ),
                      variant: GroupCardVariant.publicDiscovery,
                      onTap: () => context.go('/groups/${collection.id}'),
                      primaryAction: IconButton.filled(
                        tooltip: 'Contribute',
                        style: IconButton.styleFrom(
                          foregroundColor: context.collectColors.onImagePrimary,
                          fixedSize: const Size(42, 42),
                          minimumSize: const Size(42, 42),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () =>
                            context.go('/groups/${collection.id}/contribute'),
                        icon: const Icon(CollectIcons.donate),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HomeActionStrip extends ConsumerWidget {
  const _HomeActionStrip({
    required this.onCreate,
    required this.showCreate,
    this.primaryCollection,
  });

  final VoidCallback onCreate;
  final bool showCreate;
  final CollectCollection? primaryCollection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = primaryCollection;
    final actions = [
      if (showCreate)
        _HomeActionItem(
          icon: CollectIcons.add,
          label: 'Create',
          onTap: onCreate,
        ),
      _HomeActionItem(
        icon: CollectIcons.people,
        label: 'Join',
        onTap: () => context.go('/groups/scan'),
      ),
      _HomeActionItem(
        icon: CollectIcons.qr,
        label: 'Scan QR',
        onTap: () => context.go('/groups/scan'),
      ),
      _HomeActionItem(
        icon: CollectIcons.share,
        label: 'Share',
        onTap: () => collection == null
            ? context.go('/groups')
            : shareGroupDeepLink(
                context: context,
                ref: ref,
                collection: collection,
              ),
      ),
    ];

    return SizedBox(
      height: 58,
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: actions[index]),
            if (index != actions.length - 1) CollectSpacing.gapW8,
          ],
        ],
      ),
    );
  }
}

class _HomeActionItem extends StatelessWidget {
  const _HomeActionItem({
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
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colors.glassControl,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: SizedBox.expand(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final iconOnly = constraints.maxWidth < 92;
                final content = iconOnly
                    ? Icon(icon, color: colors.textPrimary, size: 22)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(icon, color: colors.textPrimary, size: 20),
                          CollectSpacing.gapW8,
                          Flexible(
                            child: Text(
                              label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                return Tooltip(
                  message: label,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CollectSpacing.x3,
                      vertical: CollectSpacing.x2,
                    ),
                    child: Center(child: content),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
