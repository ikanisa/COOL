import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_group_cards.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../collections/group_creation_platform.dart';
import 'app_share_service.dart';

part 'home_action_strip.dart';
part 'home_public_groups_section.dart';
part 'home_total_collected_card.dart';

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
    final contributedGroupCount = ref.watch(
      contributedCollectionIdsProvider.select((ids) => ids.length),
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
        searchLabel: 'Search',
        onSearchTap: () => context.go('/groups/search'),
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
            icon: CollectIcons.qr,
            tooltip: 'Scan QR code',
            onPressed: () => context.go('/groups/scan'),
          ),
        ],
      ),
      children: [
        _HomeTotalCollectedCard(
          totalAmount: raisedTotal,
          contributedGroupCount: contributedGroupCount,
          publicId: profile?.publicId,
          onContributedGroupsTap: () =>
              context.go('/groups?filter=contributed'),
        ),
        _HomeActionStrip(
          showCreate: showCreate,
          onCreate: () => context.go('/groups/create'),
        ),
        _PublicGroupsSection(collections: collections, summaries: summaries),
        const SectionHeader(title: 'My groups'),
        if (collections.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'No groups yet',
            message: 'Create a group or scan a group QR.',
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
              primaryAction: _HomeContributeIconButton(
                tooltip: 'Contribute',
                onPressed: () =>
                    context.go('/groups/${collection.id}/contribute'),
              ),
            ),
        const SectionHeader(title: 'Activity'),
        if (contributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message: 'MoMo confirmations appear here.',
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
