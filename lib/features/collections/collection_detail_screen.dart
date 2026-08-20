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
  bool _joining = false;

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
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    final summary = repo.summaryFor(widget.collectionId);
    final visibleContributions = repo
        .contributionsFor(widget.collectionId)
        .take(8)
        .toList();
    final profile = state.currentProfile;
    final isAdmin = profile != null && collection.creatorUserId == profile.id;
    final isMember = isAdmin || collection.isCurrentUserMember;

    return ScreenScaffold(
      title: 'Collect',
      subtitle: profile?.publicId,
      showHeader: false,
      compact: true,
      topChrome: const CollectPlainPageHeader(title: 'Group'),
      hero: CollectScreenHero(
        eyebrow: collection.collectionType.name.toUpperCase(),
        title: collection.title,
        metric: formatRwf(summary.amountRaisedRwf),
        subtitle:
            '${summary.supporterCount} '
            '${summary.supporterCount == 1 ? 'supporter' : 'supporters'}',
        icon: collectionTypeIcon(collection.collectionType),
        semanticLabel:
            '${collection.title}, ${formatRwf(summary.amountRaisedRwf)} raised, '
            '${summary.supporterCount} confirmed supporters',
        quickActions: [
          if (isMember) ...[
            CollectHeroQuickAction(
              icon: CollectIcons.donate,
              label: 'Contribute',
              onTap: () =>
                  context.go('/groups/${widget.collectionId}/contribute'),
            ),
            CollectHeroQuickAction(
              icon: CollectIcons.people,
              label: 'Members',
              onTap: () => context.go('/groups/${widget.collectionId}/members'),
            ),
            CollectHeroQuickAction(
              icon: CollectIcons.share,
              label: 'Share',
              onTap: () => context.go('/groups/${widget.collectionId}/share'),
            ),
          ] else
            CollectHeroQuickAction(
              icon: CollectIcons.people,
              label: _joining ? 'Joining' : 'Join',
              onTap: _joining ? null : () => _joinPublicGroup(collection),
            ),
          if (isAdmin)
            CollectHeroQuickAction(
              icon: CollectIcons.settings,
              label: 'Manage',
              onTap: () => context.go('/groups/${widget.collectionId}/manage'),
            ),
        ],
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      bottomAction: isAdmin
          ? null
          : CollectButton(
              label: isMember
                  ? 'Contribute'
                  : _joining
                  ? 'Joining group'
                  : 'Join group',
              icon: isMember ? CollectIcons.donate : CollectIcons.people,
              onPressed: isMember
                  ? () =>
                        context.go('/groups/${widget.collectionId}/contribute')
                  : _joining
                  ? null
                  : () => _joinPublicGroup(collection),
              expand: true,
            ),
      children: [
        if (isMember)
          InfoSecurityBanner(
            title: 'Your confirmed balance',
            message: formatRwf(summary.currentUserBalanceRwf),
            tone: CollectStatusTone.info,
          )
        else
          const InfoSecurityBanner(
            title: 'Public preview',
            message:
                'Join the group before creating a contribution request or viewing member-only details.',
            tone: CollectStatusTone.privacy,
          ),
        CollectSpacing.gap16,
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
                'Confirmed contributions appear only after independent provider verification.',
          )
        else
          _ContributionTimeline(contributions: visibleContributions),
      ],
    );
  }

  Future<void> _joinPublicGroup(CollectCollection collection) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
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
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }
}
