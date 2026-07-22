import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';
import 'group_share_service.dart';

part 'collection_detail_timeline.dart';

class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(collectionId);
    if (collection == null && state.isLoading) {
      return const ScreenScaffold(
        title: 'Group',
        showHeader: false,
        children: [
          CollectScreenLoadingState(
            title: 'Loading group',
            message: 'Refreshing group profile, balance, and activity.',
            icon: CollectIcons.collections,
            skeletonCount: 3,
          ),
        ],
      );
    }
    if (collection == null) return const MissingGroupStateScreen();
    final summary = repo.summaryFor(collectionId);
    final visibleContributions = repo
        .contributionsFor(collectionId)
        .take(8)
        .toList();
    final profile = state.currentProfile;
    final isAdmin = profile != null && collection.creatorUserId == profile.id;

    return ScreenScaffold(
      title: 'Collect',
      subtitle: profile?.publicId,
      showHeader: false,
      topChrome: CollectScreenTopChrome(
        avatarLabel: profile?.publicId ?? collection.title,
        avatarTooltip: 'Back',
        searchLabel: collection.title,
        onAvatarTap: () => goBackOrHome(context),
        onSearchTap: () => context.go('/groups'),
        actions: [
          CollectChromeAction(
            icon: CollectIcons.share,
            tooltip: 'Share group',
            onPressed: () => shareGroupDeepLink(
              context: context,
              ref: ref,
              collection: collection,
            ),
          ),
          if (isAdmin)
            CollectChromeAction(
              icon: CollectIcons.settings,
              tooltip: 'Manage group',
              onPressed: () => context.go('/groups/$collectionId/manage'),
            ),
        ],
      ),
      hero: CollectScreenHero(
        eyebrow: collection.collectionType.name.toUpperCase(),
        title: collection.title,
        metric: formatRwf(summary.amountRaisedRwf),
        subtitle: '${summary.supporterCount} supporters',
        icon: collectionTypeIcon(collection.collectionType),
        semanticLabel:
            '${formatRwf(summary.amountRaisedRwf)} raised, Open group members, ${summary.supporterCount} members',
        quickActions: [
          CollectHeroQuickAction(
            icon: CollectIcons.donate,
            label: 'Pay',
            onTap: () => context.go('/groups/$collectionId/contribute'),
          ),
          CollectHeroQuickAction(
            icon: CollectIcons.people,
            label: 'People',
            onTap: () => context.go('/groups/$collectionId/members'),
          ),
          CollectHeroQuickAction(
            icon: CollectIcons.qr,
            label: 'QR',
            onTap: () => context.go('/groups/$collectionId/share'),
          ),
          CollectHeroQuickAction(
            icon: isAdmin ? CollectIcons.settings : CollectIcons.share,
            label: isAdmin ? 'Manage' : 'Share',
            onTap: isAdmin
                ? () => context.go('/groups/$collectionId/manage')
                : () => shareGroupDeepLink(
                    context: context,
                    ref: ref,
                    collection: collection,
                  ),
          ),
        ],
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      bottomAction: isAdmin
          ? null
          : CollectButton(
              label: 'Contribute',
              icon: CollectIcons.donate,
              onPressed: () => context.go('/groups/$collectionId/contribute'),
              expand: true,
            ),
      children: [
        Semantics(
          container: true,
          header: true,
          label: 'Activity',
          child: const SectionHeader(title: 'Activity'),
        ),
        if (visibleContributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message:
                'Confirmed contributions will appear after MoMo SMS verification.',
          )
        else
          _ContributionTimeline(contributions: visibleContributions),
      ],
    );
  }
}
