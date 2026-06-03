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
    final allContributions = repo.contributionsFor(collectionId);
    final contributions = allContributions.take(6);
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
        CollectBentoGrid(
          primary: BentoMetricCell(
            label: 'Total',
            value: formatRwf(summary.amountRaisedRwf),
            detail: 'Confirmed support',
            icon: CollectIcons.money,
            tone: CollectStatusTone.success,
            emphasis: true,
          ),
          top: BentoMetricCell(
            label: 'Members',
            value: '${summary.supporterCount}',
            detail: 'Collect IDs',
            icon: CollectIcons.people,
            tone: CollectStatusTone.privacy,
          ),
          bottom: BentoMetricCell(
            label: 'Activity',
            value: '${allContributions.length}',
            detail: 'Ledger rows',
            icon: CollectIcons.check,
            tone: CollectStatusTone.success,
          ),
        ),
        InfoSecurityBanner(
          title: 'Receiver verified',
          message:
              '${collection.receiverDisplayLabel} receives MoMo contributions for this group. Public share links do not expose receiver MoMo details.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          emphasis: CollectCardEmphasis.flat,
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  'Group code: ${collection.slug}',
                  style: CollectTypography.transactionMeta(
                    context.collectColors.textMuted,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy group code',
                onPressed: () => copyToClipboard(
                  context,
                  collection.slug,
                  message: 'Group code copied.',
                ),
                icon: const Icon(CollectIcons.copy),
              ),
            ],
          ),
        ),
        QuickActionRail(
          children: [
            QuickActionButton(
              icon: CollectIcons.momo,
              label: 'Contribute',
              detail: 'MoMo',
              onTap: () => context.go('/groups/$collectionId/contribute'),
              tone: CollectStatusTone.info,
            ),
            QuickActionButton(
              icon: CollectIcons.share,
              label: 'Share',
              detail: 'Link or QR',
              onTap: () => context.go('/groups/$collectionId/share'),
              tone: CollectStatusTone.success,
            ),
            QuickActionButton(
              icon: CollectIcons.ledger,
              label: 'Ledger',
              detail: 'Confirmed',
              onTap: () => context.go('/groups/$collectionId/ledger'),
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        const SectionHeader(title: 'Recent support'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support',
            message:
                'Confirmed contributions will appear after MoMo SMS verification.',
          )
        else
          CollectCard(
            child: Column(
              children: [
                for (final contribution in contributions)
                  ActivityFeedItem(
                    title: compactCollectIdLabel(contribution.supporterLabel),
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
        CollectButton(
          label: 'Contribute with MoMo',
          icon: CollectIcons.momo,
          onPressed: () => context.go('/groups/$collectionId/contribute'),
          expand: true,
        ),
      ],
    );
  }
}
