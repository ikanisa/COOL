import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(collectionId);
    final summary = repo.summaryFor(collectionId);
    final contributions = repo.contributionsFor(collectionId).take(6);
    final profile = state.currentProfile;
    final canManage = profile != null && collection.creatorUserId == profile.id;
    return ScreenScaffold(
      title: collection.title,
      subtitle: collection.description,
      actions: [
        IconButton(
          tooltip: 'Share',
          onPressed: () => context.go('/groups/$collectionId/share'),
          icon: const Icon(CollectIcons.share),
        ),
        if (canManage)
          IconButton(
            tooltip: 'Manage',
            onPressed: () => context.go('/groups/$collectionId/manage'),
            icon: const Icon(CollectIcons.admin),
          ),
      ],
      children: [
        MoneyHeroCard(
          amount: summary.amountRaisedRwf,
          label: 'Raised so far',
          detail: '${summary.supporterCount} members contributed',
          chips: [
            const CollectStatusChip(
              label: 'Collect ID',
              tone: CollectStatusTone.privacy,
            ),
            const CollectStatusChip(label: 'SMS auto-match'),
            if (collection.receiverMomoNumber != null)
              const CollectStatusChip(
                label: 'MoMo receiver',
                tone: CollectStatusTone.success,
              ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              QuickActionButton(
                icon: CollectIcons.momo,
                label: 'Contribute',
                detail: 'Direct MOMO',
                onTap: () => context.go('/groups/$collectionId/contribute'),
                tone: CollectStatusTone.info,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.share,
                label: 'Share',
                detail: 'Link or QR',
                onTap: () => context.go('/groups/$collectionId/share'),
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.ledger,
                label: 'Ledger',
                detail: 'Verified',
                onTap: () => context.go('/groups/$collectionId/ledger'),
                tone: CollectStatusTone.privacy,
              ),
            ],
          ),
        ),
        const SecurityNotice(
          title: 'Member privacy',
          message:
              'Collect uses 6-digit IDs for matching. Phone numbers, MoMo numbers, real names, and raw SMS stay private.',
        ),
        const SectionHeader(title: 'Recent support'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message: 'Confirmed contributions appear after MoMo SMS matching.',
          )
        else
          CollectCard(
            child: Column(
              children: [
                for (final contribution in contributions)
                  ActivityFeedItem(
                    title: contribution.supporterLabel,
                    amount: contribution.amountRwf,
                    meta: contribution.createdAt
                        .toLocal()
                        .toString()
                        .split('.')
                        .first,
                    transactionId: contribution.transactionId,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
