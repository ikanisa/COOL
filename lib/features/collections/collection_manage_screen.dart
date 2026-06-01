import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class CollectionManageScreen extends ConsumerWidget {
  const CollectionManageScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(collectionId);
    final summary = repo.summaryFor(collectionId);
    final health = ref.watch(ownerGroupHealthProvider(collectionId));

    return ScreenScaffold(
      title: 'Manage',
      subtitle: collection.title,
      children: [
        MoneyHeroCard(
          amount: summary.amountRaisedRwf,
          label: 'Confirmed support',
          detail: '${summary.supporterCount} ledger entries',
        ),
        InfoSecurityBanner(
          title: 'Receiver',
          message:
              '${collection.receiverDisplayLabel} receives this group. Receiver MoMo can be changed from the owner-only MoMo screen.',
          tone: CollectStatusTone.privacy,
        ),
        health.when(
          data: (item) => CollectCard(
            emphasis: CollectCardEmphasis.flat,
            child: Column(
              children: [
                CollectListTile(
                  leading: item.ready
                      ? CollectIcons.check
                      : CollectIcons.warning,
                  title: item.ready
                      ? 'Group health ready'
                      : 'Group needs attention',
                  subtitle:
                      '${item.pendingPaymentIntents} pending · ${item.needsReviewEvents} review',
                  onTap: () => context.go('/groups/$collectionId/owner'),
                ),
              ],
            ),
          ),
          loading: () => const LoadingSkeleton(lines: 2),
          error: (error, _) => InfoSecurityBanner(
            title: 'Health unavailable',
            message: error.toString(),
            tone: CollectStatusTone.warning,
          ),
        ),
        CollectCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollectListTile(
                leading: CollectIcons.info,
                title: 'Group profile',
                subtitle: collection.description.isEmpty
                    ? 'No description'
                    : collection.description,
              ),
              CollectListTile(
                leading: CollectIcons.money,
                title: 'Target amount',
                subtitle:
                    'Optional target tracking is not enabled for this group model yet. Current raised: ${formatRwf(summary.amountRaisedRwf)}.',
              ),
              CollectListTile(
                leading: CollectIcons.dashboard,
                title: 'Owner',
                subtitle: 'Health, MoMo, members.',
                onTap: () => context.go('/groups/$collectionId/owner'),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Share',
                subtitle: 'Link, QR, chat.',
                onTap: () => context.go('/groups/$collectionId/share'),
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger',
                subtitle: 'Activity.',
                onTap: () => context.go('/groups/$collectionId/ledger'),
              ),
              CollectListTile(
                leading: CollectIcons.momo,
                title: 'MoMo',
                subtitle: collection.receiverDisplayLabel,
                onTap: () => context.go('/groups/$collectionId/owner/receiver'),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Members',
                subtitle: 'Active.',
                onTap: () => context.go('/groups/$collectionId/members'),
              ),
              const CollectListTile(
                leading: CollectIcons.warning,
                title: 'Close group',
                subtitle:
                    'Closing groups is not enabled in this build. Keep sharing paused manually.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
