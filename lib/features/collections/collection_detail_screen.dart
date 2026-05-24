import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
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
    final target = collection.targetAmountRwf;
    final progress = target == null || target == 0
        ? 0.0
        : summary.amountRaisedRwf / target;

    return ScreenScaffold(
      title: collection.title,
      subtitle: collection.description,
      actions: [
        IconButton(
          tooltip: 'Share',
          onPressed: () => context.go('/collections/$collectionId/share'),
          icon: const Icon(CollectIcons.share),
        ),
        if (canManage)
          IconButton(
            tooltip: 'Manage',
            onPressed: () => context.go('/collections/$collectionId/manage'),
            icon: const Icon(CollectIcons.admin),
          ),
      ],
      children: [
        MoneyHeroCard(
          amount: summary.amountRaisedRwf,
          label: 'Raised so far',
          detail: target == null
              ? '${summary.supporterCount} supporters'
              : '${summary.supporterCount} supporters of ${formatRwf(target)}',
          chips: [
            CollectStatusChip(label: collection.category),
            CollectStatusChip(
              label: collection.publicStatus.replaceAll('_', ' '),
              tone: statusToneFromText(collection.publicStatus),
            ),
            CollectStatusChip(
              label: collection.allowAnonymous
                  ? 'Anonymous OK'
                  : 'Named support',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        if (target != null)
          CollectProgressBar(
            value: progress,
            label: '${(progress.clamp(0.0, 1.0) * 100).round()}% funded',
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              QuickActionButton(
                icon: CollectIcons.momo,
                label: 'Contribute',
                detail: 'Direct MOMO',
                onTap: () =>
                    context.go('/collections/$collectionId/contribute'),
                tone: CollectStatusTone.info,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.share,
                label: 'Share',
                detail: 'Safe link',
                onTap: () => context.go('/collections/$collectionId/share'),
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gapW12,
              QuickActionButton(
                icon: CollectIcons.ledger,
                label: 'Ledger',
                detail: 'Verified',
                onTap: () => context.go('/collections/$collectionId/ledger'),
                tone: CollectStatusTone.privacy,
              ),
            ],
          ),
        ),
        const SecurityNotice(
          title: 'Contributor privacy',
          message:
              'Public activity uses safe names only. Phone numbers, MOMO numbers, and raw SMS stay private.',
        ),
        const SectionHeader(title: 'Recent support'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message:
                'Confirmed contributions will appear here after MOMO verification.',
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
