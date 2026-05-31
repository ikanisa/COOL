import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      subtitle: 'Groups verified from MoMo SMS.',
      actions: [
        IconButton.filled(
          tooltip: 'Create group',
          onPressed: () => openGroupCreation(context),
          icon: const Icon(CollectIcons.add),
        ),
      ],
      children: [
        MoneyHeroCard(
          amount: raisedTotal,
          label: 'Raised across Collect',
          detail: '$collectionCount groups · $pendingTotal pending intents',
          chips: const [
            CollectStatusChip(
              label: 'SMS auto-match',
              tone: CollectStatusTone.success,
            ),
            CollectStatusChip(
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
                detail: 'MoMo number',
                onTap: () => context.go('/profile/setup'),
                tone: CollectStatusTone.privacy,
              ),
            ],
          ),
        ),
        const SecurityNotice(
          title: 'SMS-first verification',
          message:
              'Members initiate MoMo from Collect. MoMo SMS is parsed and matched automatically to pending intents.',
        ),
        InsightCard(
          title: 'Pending allocation',
          message: pendingTotal == 0
              ? 'No pending intents. Confirmed contributions are in the ledger.'
              : '$pendingTotal contributions are waiting for MoMo SMS matching.',
          icon: CollectIcons.shield,
          tone: pendingTotal == 0
              ? CollectStatusTone.success
              : CollectStatusTone.warning,
          actionLabel: 'Open ledger',
          onAction: collections.isEmpty
              ? null
              : () => context.go('/groups/${collections.first.id}/ledger'),
        ),
        const SectionHeader(title: 'Groups'),
        if (collections.isEmpty)
          EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'Create your first group',
            message:
                'Add a group name, use the MoMo number from your profile, then share the link or QR code.',
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
