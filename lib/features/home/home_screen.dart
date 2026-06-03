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
    final pendingAmount = paymentIntents
        .where((intent) => intent.status == 'pending')
        .fold<int>(0, (sum, intent) => sum + intent.expectedAmountRwf);
    return ScreenScaffold(
      title: 'Good morning',
      subtitle: profile == null ? null : '#${profile.publicId}',
      actions: [
        _NotificationAction(hasUnread: paymentIntents.isNotEmpty),
        IconButton.filledTonal(
          tooltip: 'Profile',
          onPressed: () => context.go('/settings/profile'),
          icon: const Icon(CollectIcons.profile),
        ),
      ],
      children: [
        _HomeTotalCollectedCard(
          confirmedAmount: raisedTotal,
          pendingAmount: pendingAmount,
          failedAmount: 0,
          collectionCount: collectionCount,
        ),
        _HomeActionStrip(
          primaryCollectionId: collections.isEmpty
              ? null
              : collections.first.id,
          onCreate: () => openGroupCreation(context),
        ),
        const _PublicCollectionsSection(),
        const SectionHeader(title: 'My groups'),
        if (collections.isEmpty)
          EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'No groups yet',
            message: 'Create a group or join with a shared Collect link.',
            action: CollectButton(
              label: 'Create group',
              icon: CollectIcons.add,
              onPressed: () => openGroupCreation(context),
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
              primaryAction: CollectButton(
                label: 'Contribute',
                icon: CollectIcons.momo,
                onPressed: () =>
                    context.go('/groups/${collection.id}/contribute'),
                expand: true,
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
        CollectButton(
          label: 'Open groups',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups'),
          expand: true,
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filledTonal(
          tooltip: 'Notifications',
          onPressed: () => context.go('/notifications'),
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
    required this.confirmedAmount,
    required this.pendingAmount,
    required this.failedAmount,
    required this.collectionCount,
  });

  final int confirmedAmount;
  final int pendingAmount;
  final int failedAmount;
  final int collectionCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final totalAmount = confirmedAmount + pendingAmount + failedAmount;
    final confirmedPercent = _percent(confirmedAmount, totalAmount);
    final pendingPercent = _percent(pendingAmount, totalAmount);
    final failedPercent = _percent(failedAmount, totalAmount);

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
        child: Stack(
          children: [
            const Positioned(
              right: -38,
              top: -52,
              child: _HomeHeroOrb(size: 176, alpha: 0.18),
            ),
            const Positioned(
              right: -22,
              bottom: -46,
              child: _HomeHeroOrb(size: 122, alpha: 0.10),
            ),
            Padding(
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
                        const TextSpan(text: ' active groups'),
                      ],
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  CollectSpacing.gap24,
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 500;
                      final stats = [
                        _HomeCollectionStat(
                          label: 'Confirmed',
                          amount: confirmedAmount,
                          percent: confirmedPercent,
                          color: colors.success,
                        ),
                        _HomeCollectionStat(
                          label: 'Pending',
                          amount: pendingAmount,
                          percent: pendingPercent,
                          color: colors.warning,
                        ),
                        _HomeCollectionStat(
                          label: 'Failed',
                          amount: failedAmount,
                          percent: failedPercent,
                          color: colors.textMuted,
                        ),
                      ];
                      if (compact) {
                        return Column(
                          children: [
                            for (var index = 0; index < stats.length; index++)
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == stats.length - 1
                                      ? 0
                                      : CollectSpacing.x3,
                                ),
                                child: stats[index],
                              ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          for (
                            var index = 0;
                            index < stats.length;
                            index++
                          ) ...[
                            Expanded(child: stats[index]),
                            if (index < stats.length - 1)
                              Container(
                                width: 1,
                                height: 58,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: CollectSpacing.x4,
                                ),
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _percent(int amount, int total) {
    if (total <= 0) return '0%';
    final value = (amount / total) * 100;
    return value == value.roundToDouble()
        ? '${value.round()}%'
        : '${value.toStringAsFixed(1)}%';
  }
}

class _HomeHeroOrb extends StatelessWidget {
  const _HomeHeroOrb({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alpha),
        shape: BoxShape.circle,
      ),
      child: SizedBox(width: size, height: size),
    );
  }
}

class _HomeCollectionStat extends StatelessWidget {
  const _HomeCollectionStat({
    required this.label,
    required this.amount,
    required this.percent,
    required this.color,
  });

  final String label;
  final int amount;
  final String percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox(width: 10, height: 10),
            ),
            CollectSpacing.gapW8,
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        CollectSpacing.gap8,
        Text(
          formatRwf(amount),
          style: CollectTypography.amountLarge(Colors.white),
        ),
        CollectSpacing.gap4,
        Text(
          percent,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.66),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _HomeActionStrip extends StatelessWidget {
  const _HomeActionStrip({required this.onCreate, this.primaryCollectionId});

  final VoidCallback onCreate;
  final String? primaryCollectionId;

  @override
  Widget build(BuildContext context) {
    final collectionId = primaryCollectionId;
    final actions = [
      _HomeActionItem(icon: CollectIcons.add, label: 'Create', onTap: onCreate),
      _HomeActionItem(
        icon: CollectIcons.people,
        label: 'Join',
        onTap: () => context.go('/groups/join'),
      ),
      _HomeActionItem(
        icon: Icons.volunteer_activism_rounded,
        label: 'Contribute',
        highlighted: true,
        onTap: () => collectionId == null
            ? context.go('/groups')
            : context.go('/groups/$collectionId/contribute'),
      ),
      _HomeActionItem(
        icon: CollectIcons.qr,
        label: 'Scan QR',
        onTap: () => context.go('/groups/join'),
      ),
      _HomeActionItem(
        icon: CollectIcons.share,
        label: 'Share',
        onTap: () => collectionId == null
            ? context.go('/groups')
            : context.go('/groups/$collectionId/share'),
      ),
    ];

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: actions.length,
        separatorBuilder: (_, _) => CollectSpacing.gapW12,
        itemBuilder: (context, index) => actions[index],
      ),
    );
  }
}

class _HomeActionItem extends StatelessWidget {
  const _HomeActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = highlighted ? Colors.white : colors.textPrimary;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: highlighted ? colors.actionCrimson : colors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x2,
                vertical: CollectSpacing.x2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 30),
                  CollectSpacing.gap8,
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _PublicCollectionsSection extends StatelessWidget {
  const _PublicCollectionsSection();

  @override
  Widget build(BuildContext context) {
    const collections = [
      _PublicCollection(
        category: 'Football',
        title: 'Kigali Lions Away Kit',
        description: "Help fans support the team's new season kit",
        raisedRwf: 275000,
        goalRwf: 500000,
        supporters: 124,
        icon: Icons.sports_soccer_rounded,
        collectionId: 'col-team',
      ),
      _PublicCollection(
        category: 'Church',
        title: 'St Michel Building Fund',
        description: 'Building a stronger church for our community',
        raisedRwf: 350000,
        goalRwf: 800000,
        supporters: 198,
        icon: Icons.church_rounded,
        collectionId: 'col-church',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Public collections',
          actionLabel: 'View all',
          onAction: () => context.go('/groups'),
        ),
        CollectSpacing.gap12,
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 680;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < collections.length; index++) ...[
                    Expanded(
                      child: _PublicCollectionCard(
                        collection: collections[index],
                      ),
                    ),
                    if (index < collections.length - 1) CollectSpacing.gapW12,
                  ],
                ],
              );
            }
            return SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.zero,
                itemCount: collections.length,
                separatorBuilder: (_, _) => CollectSpacing.gapW12,
                itemBuilder: (context, index) => SizedBox(
                  width: 320,
                  child: _PublicCollectionCard(collection: collections[index]),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PublicCollection {
  const _PublicCollection({
    required this.category,
    required this.title,
    required this.description,
    required this.raisedRwf,
    required this.goalRwf,
    required this.supporters,
    required this.icon,
    required this.collectionId,
  });

  final String category;
  final String title;
  final String description;
  final int raisedRwf;
  final int goalRwf;
  final int supporters;
  final IconData icon;
  final String collectionId;
}

class _PublicCollectionCard extends StatelessWidget {
  const _PublicCollectionCard({required this.collection});

  final _PublicCollection collection;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final progress = collection.goalRwf <= 0
        ? 0.0
        : (collection.raisedRwf / collection.goalRwf).clamp(0.0, 1.0);
    return CollectCard(
      padding: const EdgeInsets.all(CollectSpacing.x4),
      onTap: () => context.go('/groups/${collection.collectionId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _PublicChip(label: collection.category)),
              Icon(CollectIcons.check, color: colors.success, size: 24),
            ],
          ),
          CollectSpacing.gap12,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.info.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 58,
                  height: 58,
                  child: Icon(collection.icon, color: colors.info, size: 34),
                ),
              ),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    CollectSpacing.gap4,
                    Text(
                      collection.description,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          CollectSpacing.gap12,
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatRwf(collection.raisedRwf),
                  style: CollectTypography.amountCompact(colors.textPrimary),
                ),
                TextSpan(
                  text: ' raised',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          CollectSpacing.gap4,
          Text(
            'Goal ${formatRwf(collection.goalRwf)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          CollectSpacing.gap8,
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              color: colors.actionCrimson,
              backgroundColor: colors.surfaceMuted,
            ),
          ),
          CollectSpacing.gap12,
          Row(
            children: [
              Icon(CollectIcons.people, size: 18, color: colors.textSecondary),
              CollectSpacing.gapW8,
              Expanded(
                child: Text(
                  '${collection.supporters} supporters',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.go('/groups/${collection.collectionId}/contribute'),
                child: const Text('Support'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublicChip extends StatelessWidget {
  const _PublicChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.info.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x3,
            vertical: CollectSpacing.x1,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.info,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
