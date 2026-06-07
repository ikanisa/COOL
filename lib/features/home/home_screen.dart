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
      children: [
        _HomeBrandHeader(
          publicId: profile?.publicId,
          hasUnread: paymentIntents.isNotEmpty,
        ),
        _HomeTotalCollectedCard(
          totalAmount: raisedTotal,
          collectionCount: collectionCount,
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

class _HomeBrandHeader extends StatelessWidget {
  const _HomeBrandHeader({required this.hasUnread, this.publicId});

  final String? publicId;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Collect',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (publicId != null) ...[
                CollectSpacing.gap4,
                Row(
                  children: [
                    Icon(
                      CollectIcons.profile,
                      color: colors.textSecondary,
                      size: 18,
                    ),
                    CollectSpacing.gapW8,
                    Text(
                      publicId!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _NotificationAction(hasUnread: hasUnread),
        CollectSpacing.gapW8,
        IconButton.filled(
          tooltip: 'Profile',
          onPressed: () => context.go('/settings/profile'),
          style: IconButton.styleFrom(
            backgroundColor: colors.surfaceRaised,
            foregroundColor: colors.textPrimary,
          ),
          icon: const Icon(CollectIcons.profile),
        ),
      ],
    );
  }
}

class _NotificationAction extends StatelessWidget {
  const _NotificationAction({required this.hasUnread});

  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filled(
          tooltip: 'Notifications',
          onPressed: () => context.go('/notifications'),
          style: IconButton.styleFrom(
            backgroundColor: colors.surfaceRaised,
            foregroundColor: colors.textPrimary,
          ),
          icon: const Icon(CollectIcons.pending),
        ),
        if (hasUnread)
          Positioned(
            right: 7,
            top: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.collectColors.info,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 9, height: 9),
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
  });

  final int totalAmount;
  final int collectionCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF6E001D), Color(0xFF270611)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
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
              Text(
                'TOTAL COLLECTED',
                style: CollectTypography.eyebrowLabel(
                  Colors.white.withValues(alpha: 0.82),
                ),
              ),
              CollectSpacing.gap12,
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatRwf(totalAmount),
                  style: CollectTypography.amountDisplay(Colors.white),
                ),
              ),
              CollectSpacing.gap4,
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Across '),
                    TextSpan(
                      text: '$collectionCount',
                      style: const TextStyle(
                        color: Color(0xFFFF5F89),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: collectionCount == 1
                          ? ' active group'
                          : ' active groups',
                    ),
                  ],
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              itemCount: actions.length,
              separatorBuilder: (_, _) => CollectSpacing.gapW8,
              itemBuilder: (context, index) =>
                  SizedBox(width: 96, child: actions[index]),
            ),
          );
        }

        return SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.zero,
            itemCount: actions.length,
            separatorBuilder: (_, _) => CollectSpacing.gapW8,
            itemBuilder: (context, index) =>
                SizedBox(width: 112, child: actions[index]),
          ),
        );
      },
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
        color: colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          onTap: onTap,
          borderRadius: CollectRadius.pillBorder,
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x3,
                vertical: CollectSpacing.x2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: colors.textPrimary, size: 22),
                  CollectSpacing.gapW8,
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
