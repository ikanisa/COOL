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

part 'home_public_groups_section.dart';

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
      topChrome: CollectScreenTopChrome(
        avatarLabel: profile?.publicId,
        avatarTooltip: 'Profile',
        searchLabel: 'Search groups',
        onAvatarTap: () => context.go('/settings'),
        onSearchTap: () => context.go('/groups'),
      ),
      hero: isInitialLoading
          ? null
          : CollectScreenHero(
              title: 'Total collected',
              metric: formatRwf(raisedTotal),
              subtitle: _supportedGroupCountLabel(contributedGroupCount),
              quickActions: [
                if (showCreate)
                  CollectHeroQuickAction(
                    icon: CollectIcons.add,
                    label: 'Create',
                    onTap: () => context.go('/groups/create'),
                  )
                else
                  CollectHeroQuickAction(
                    icon: CollectIcons.collections,
                    label: 'Groups',
                    onTap: () => context.go('/groups'),
                  ),
                CollectHeroQuickAction(
                  icon: CollectIcons.qr,
                  label: 'Scan QR',
                  onTap: () => context.go('/groups/scan'),
                ),
                CollectHeroQuickAction(
                  key: const Key('home_supported_groups_chip'),
                  icon: CollectIcons.people,
                  label: 'Supported',
                  tooltip: 'Supported groups',
                  onTap: () => context.go('/groups?filter=contributed'),
                ),
                CollectHeroQuickAction(
                  icon: CollectIcons.share,
                  label: 'Share',
                  onTap: () => shareCollectApp(context: context, ref: ref),
                ),
              ],
            ),
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
              if (collections.isNotEmpty) ...[
                const SectionHeader(title: 'My groups'),
                GroupListPanel(
                  collections: collections,
                  summaries: summaries,
                  onGroupTap: (collection) =>
                      context.go('/groups/${collection.id}'),
                ),
              ],
              _PublicGroupsSection(
                collections: collections,
                summaries: summaries,
              ),
            ],
    );
  }
}

String _supportedGroupCountLabel(int count) =>
    '$count supported ${count == 1 ? 'group' : 'groups'}';
