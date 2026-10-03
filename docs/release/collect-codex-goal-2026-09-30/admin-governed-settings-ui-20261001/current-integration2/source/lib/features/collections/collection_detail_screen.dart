import 'package:flutter/material.dart';
import '../profile/member_profile_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_data_load_failure.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';

part 'collection_detail_timeline.dart';

class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
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
    if (collection == null && state.lastError != null) {
      return ScreenScaffold(
        title: 'Group',
        showHeader: false,
        children: [
          CollectDataLoadFailure(
            onRetry: () =>
                ref.read(collectRepositoryProvider.notifier).loadInitial(),
          ),
        ],
      );
    }
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    final summary = repo.summaryFor(widget.collectionId);
    final totalLabel = summary == null
        ? 'Not available'
        : formatCurrencyTotals(summary.totalsByCurrency, separator: '\n');
    final historyQuery = MemberHistoryQuery(collectionId: widget.collectionId);
    final history = ref.watch(memberHistoryProvider(historyQuery));
    final visibleContributions =
        history.page?.items.take(8).toList() ?? const <Contribution>[];
    final profile = state.currentProfile;
    final isAdmin = profile != null && collection.creatorUserId == profile.id;
    final canManage =
        isAdmin && !collection.isPlatformSponsored && !collection.isPublic;
    final isMember = isAdmin || collection.isCurrentUserMember;
    final canContribute = collection.isPublic || isMember;
    final contributionActionLabel = isMember
        ? 'Contribute'
        : 'Contribute & Join';

    return ScreenScaffold(
      title: 'Collect',
      subtitle: profile?.publicId,
      showHeader: false,
      compact: true,
      topChrome: const CollectPlainPageHeader(title: 'Group'),
      hero: CollectScreenHero(
        title: collection.title,
        metric: totalLabel,
        subtitleWidget: CollectPeopleCount(
          count: summary?.supporterCount,
          color: CollectRuntimeTokens.chromeMutedForeground(
            context.collectColors,
          ),
        ),
        subtitleSemanticLabel:
            summary?.supporterCountSemantics ?? 'Contributor count unavailable',
        icon: collectionTypeIcon(collection.collectionType),
        semanticLabel:
            '${collection.title}, '
            '${summary == null ? 'Group total unavailable' : '$totalLabel raised'}, '
            '${summary?.supporterCountSemantics ?? 'Contributor count unavailable'}',
        quickActions: [
          if (canContribute) ...[
            CollectHeroQuickAction(
              icon: CollectIcons.donate,
              label: contributionActionLabel,
              onTap: () =>
                  context.go('/groups/${widget.collectionId}/contribute'),
            ),
            if (isMember)
              CollectHeroQuickAction(
                icon: CollectIcons.people,
                label: 'Members',
                onTap: () =>
                    context.go('/groups/${widget.collectionId}/members'),
              ),
            CollectHeroQuickAction(
              icon: CollectIcons.share,
              label: 'Share',
              onTap: () => context.go('/groups/${widget.collectionId}/share'),
            ),
          ] else
            CollectHeroQuickAction(
              icon: CollectIcons.people,
              label: 'Join',
              onTap: () => _joinPrivateGroup(collection),
            ),
          if (canManage)
            CollectHeroQuickAction(
              icon: CollectIcons.settings,
              label: 'Manage',
              onTap: () => context.go('/groups/${widget.collectionId}/manage'),
            ),
        ],
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      bottomAction: canManage
          ? null
          : CollectButton(
              label: canContribute ? contributionActionLabel : 'Join group',
              icon: canContribute ? CollectIcons.donate : CollectIcons.people,
              onPressed: canContribute
                  ? () =>
                        context.go('/groups/${widget.collectionId}/contribute')
                  : () => _joinPrivateGroup(collection),
              expand: true,
            ),
      children: [
        if (isMember) ...[
          InfoSecurityBanner(
            title: 'Your confirmed balance',
            message: summary == null
                ? 'Not available'
                : formatCurrencyTotals(summary.ownBalancesByCurrency),
            tone: CollectStatusTone.info,
          ),
          CollectSpacing.gap16,
        ] else if (!collection.isPublic) ...[
          const InfoSecurityBanner(
            title: 'Private group',
            message: 'Use a valid group invitation to join this private group.',
            tone: CollectStatusTone.privacy,
          ),
          CollectSpacing.gap16,
        ],
        const SectionHeader(title: 'Activity'),
        if (history.loading && history.page == null)
          const Center(child: CircularProgressIndicator())
        else if (history.page == null)
          CollectDataLoadFailure(
            onRetry: () => ref
                .read(memberHistoryProvider(historyQuery).notifier)
                .refresh(),
          )
        else if (visibleContributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No contributions yet',
            message:
                'Confirmed contributions appear only after independent provider verification.',
          )
        else
          _ContributionTimeline(contributions: visibleContributions),
      ],
    );
  }

  Future<void> _joinPrivateGroup(CollectCollection collection) async {
    try {
      await requireMemberProfileReady(context, ref);
      if (!mounted) return;
      await ref
          .read(collectRepositoryProvider.notifier)
          .joinGroupBySlug(collection.slug);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You joined the group.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not join this group.')),
      );
    }
  }
}
