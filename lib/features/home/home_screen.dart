import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    final collectionCount = ref.watch(
      collectRepositoryProvider.select((state) => state.collections.length),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    final pendingTotal = ref.watch(pendingPaymentCountProvider);
    final raisedTotal = ref.watch(raisedTotalProvider);
    final contributions = ref.watch(
      collectRepositoryProvider.select((state) => state.contributions),
    );

    return ScreenScaffold(
      title: 'Collect',
      actions: [
        IconButton.filled(
          tooltip: 'Create group',
          onPressed: () => openGroupCreation(context),
          icon: const Icon(CollectIcons.add),
        ),
      ],
      children: [
        CollectBentoGrid(
          primary: BentoMetricCell(
            label: 'Total',
            value: formatRwf(raisedTotal),
            detail: '$collectionCount groups',
            icon: CollectIcons.money,
            tone: CollectStatusTone.success,
            emphasis: true,
          ),
          top: BentoMetricCell(
            label: 'Groups',
            value: '$collectionCount',
            detail: 'Active',
            icon: CollectIcons.collections,
            tone: CollectStatusTone.info,
          ),
          bottom: BentoMetricCell(
            label: 'Payments',
            value: '$pendingTotal',
            detail: 'Open',
            icon: CollectIcons.pending,
            tone: pendingTotal == 0
                ? CollectStatusTone.neutral
                : CollectStatusTone.warning,
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              QuickActionButton(
                icon: CollectIcons.add,
                label: 'Create',
                detail: 'New group',
                onTap: () => openGroupCreation(context),
                tone: CollectStatusTone.info,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.collections,
                label: 'Groups',
                detail: '$collectionCount active',
                onTap: () => context.go('/groups'),
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.profile,
                label: 'Profile',
                detail: 'MoMo',
                onTap: () => context.go('/settings/profile'),
                tone: CollectStatusTone.privacy,
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'Groups'),
        if (collections.isEmpty)
          EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'Create group',
            message: 'Name, receiver, share.',
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
            message: '',
          )
        else
          CollectCard(
            child: Column(
              children: [
                for (final contribution in contributions.take(5))
                  ActivityFeedItem(
                    title: compactCollectIdLabel(contribution.supporterLabel),
                    amount: contribution.amountRwf,
                    meta: contribution.createdAt
                        .toLocal()
                        .toString()
                        .split('.')
                        .first,
                    transactionId: contribution.transactionId,
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
