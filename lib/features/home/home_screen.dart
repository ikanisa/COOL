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
    final state = ref.watch(collectRepositoryProvider);
    final isInitialLoading =
        state.isLoading &&
        state.collections.isEmpty &&
        state.contributions.isEmpty &&
        state.paymentIntents.isEmpty;
    final collections = ref.watch(homeCollectionsProvider);
    final profile = state.currentProfile;
    final contributedGroupCount = ref.watch(
      contributedCollectionIdsProvider.select((ids) => ids.length),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    final raisedTotal = ref.watch(raisedTotalProvider);
    final contributions = state.contributions;
    final showCreate = shouldShowGroupCreationEntryOnThisPlatform();
    return ScreenScaffold(
      title: 'Home',
      showHeader: false,
      compact: true,
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: isInitialLoading
          ? const [
              CollectScreenLoadingState(
                title: 'Loading home',
                message: 'Refreshing groups, balances, and recent activity.',
                icon: CollectIcons.home,
                skeletonCount: 3,
              ),
            ]
          : [
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
              _PublicGroupsSection(
                collections: collections,
                summaries: summaries,
              ),
              if (collections.isNotEmpty) ...[
                const SectionHeader(title: 'My groups'),
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
              ],
              if (contributions.isNotEmpty) ...[
                const SectionHeader(title: 'Activity'),
                CollectCard(
                  child: Column(
                    children: [
                      for (final contribution in contributions.take(5))
                        ActivityFeedItem(
                          title: compactCollectIdLabel(
                            contribution.supporterLabel,
                          ),
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
            ],
    );
  }
}
