import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(homeCollectionsProvider);
    final collectionCount = ref.watch(
      collectRepositoryProvider.select((state) => state.collections.length),
    );
    final receiverModeEnabled = ref.watch(
      collectRepositoryProvider.select((state) => state.receiverModeEnabled),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    final pendingTotal = ref.watch(pendingPaymentCountProvider);
    final raisedTotal = ref.watch(raisedTotalProvider);
    final contributions = ref.watch(
      collectRepositoryProvider.select((state) => state.contributions),
    );

    return ScreenScaffold(
      title: 'Collect',
      subtitle: 'Community money, clear and verified.',
      actions: [
        IconButton.filled(
          tooltip: 'Create collection',
          onPressed: () => context.go('/collections/create'),
          icon: const Icon(CollectIcons.add),
        ),
      ],
      children: [
        MoneyHeroCard(
          amount: raisedTotal,
          label: 'Raised across Collect',
          detail: '$collectionCount goals · $pendingTotal pending MOMO checks',
          chips: [
            CollectStatusChip(
              label: receiverModeEnabled ? 'Receiver mode on' : 'Manual review',
              tone: receiverModeEnabled
                  ? CollectStatusTone.success
                  : CollectStatusTone.neutral,
            ),
            const CollectStatusChip(
              label: 'Direct MOMO',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              QuickActionButton(
                icon: CollectIcons.add,
                label: 'Create',
                detail: 'New goal',
                onTap: () => context.go('/collections/create'),
                tone: CollectStatusTone.info,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.collections,
                label: 'Goals',
                detail: '$collectionCount active',
                onTap: () => context.go('/collections'),
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.sms,
                label: 'Verify',
                detail: receiverModeEnabled ? 'Receiver on' : 'Paste SMS',
                onTap: () => context.go('/receiver'),
                tone: CollectStatusTone.privacy,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.public,
                label: 'Public',
                detail: 'Browse',
                onTap: () => context.go('/public'),
                tone: CollectStatusTone.warning,
              ),
            ],
          ),
        ),
        const SecurityNotice(
          title: 'MOMO-first safety',
          message:
              'Contributors pay receivers directly. Collect verifies notifications and keeps raw SMS private.',
        ),
        InsightCard(
          title: 'Keep trust visible',
          message: pendingTotal == 0
              ? 'No pending payments. Confirmed support is ready in the ledger.'
              : '$pendingTotal payments need MOMO evidence review.',
          icon: CollectIcons.shield,
          tone: pendingTotal == 0
              ? CollectStatusTone.success
              : CollectStatusTone.warning,
          actionLabel: 'Open ledger',
          onAction: collections.isEmpty
              ? null
              : () => context.go('/collections/${collections.first.id}/ledger'),
        ),
        const SectionHeader(title: 'Active goals'),
        if (collections.isEmpty)
          EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'Start a goal',
            message:
                'Create a private collection, set the receiver, then share only when the copy is safe.',
            action: CollectButton(
              label: 'Create collection',
              icon: CollectIcons.add,
              onPressed: () => context.go('/collections/create'),
            ),
          )
        else
          for (final collection in collections)
            CollectionGoalCard(
              collection: collection,
              summary:
                  summaries[collection.id] ??
                  const CollectionSummary(
                    amountRaisedRwf: 0,
                    supporterCount: 0,
                  ),
              onTap: () => context.go('/collections/${collection.id}'),
              primaryAction: CollectButton(
                label: 'Contribute',
                icon: CollectIcons.momo,
                onPressed: () =>
                    context.go('/collections/${collection.id}/contribute'),
                expand: true,
              ),
            ),
        const SectionHeader(title: 'Activity'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No verified support yet',
            message: 'Confirmed MOMO contributions will appear here.',
          )
        else
          CollectCard(
            child: Column(
              children: [
                for (final contribution in contributions.take(5))
                  ActivityFeedItem(
                    title: contribution.supporterLabel,
                    amount: contribution.amountRwf,
                    meta: 'Verified MOMO contribution',
                    transactionId: contribution.transactionId,
                    onTap: () => context.go(
                      '/collections/${contribution.collectionId}/ledger',
                    ),
                  ),
              ],
            ),
          ),
        CollectButton(
          label: 'Explore public collections',
          icon: CollectIcons.public,
          onPressed: () => context.go('/public'),
          expand: true,
        ),
      ],
    );
  }
}
