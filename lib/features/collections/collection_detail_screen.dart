import 'dart:async';

import 'package:flutter/material.dart';
import '../profile/member_profile_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/models/contribution_record_copy.dart';
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
  int _joinOperation = 0;
  int _routeGeneration = 0;
  String? _joiningGroupId, _joiningProfileId;
  int? _joiningSession;
  CollectRepository? _joiningRepository;

  @override
  void didUpdateWidget(covariant CollectionDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionId != widget.collectionId) {
      _routeGeneration++;
      _joinOperation++;
      _joiningGroupId = null;
      _joiningProfileId = null;
      _joiningSession = null;
      _joiningRepository = null;
    }
  }

  bool _isJoining(
    CollectRepository repository,
    String groupId,
    String? profileId,
    int session,
  ) =>
      _joiningGroupId == groupId &&
      _joiningProfileId == profileId &&
      _joiningSession == session &&
      identical(_joiningRepository, repository);

  bool _matchesActionScope(
    CollectCollection collection,
    CollectRepository repository,
    String? profileId,
    int session,
    int routeGeneration,
    bool isLive,
  ) =>
      mounted &&
      widget.collectionId == collection.id &&
      routeGeneration == _routeGeneration &&
      identical(ref.read(collectRepositoryProvider.notifier), repository) &&
      repository.sessionGeneration == session &&
      repository.isLive == isLive &&
      ref.read(collectRepositoryProvider).currentProfile?.id == profileId &&
      identical(repository.maybeCollectionById(collection.id), collection);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    if (collection == null &&
        (state.isLoading || state.publicDiscoveryLoading)) {
      return const ScreenScaffold(
        title: 'Group',
        showHeader: false,
        children: [
          CollectScreenLoadingState(
            title: 'Loading group',
            message: 'Refreshing group profile, recorded totals, and activity.',
            icon: CollectIcons.collections,
            skeletonCount: 3,
          ),
        ],
      );
    }
    if (collection == null &&
        (state.lastError != null ||
            state.publicDiscoveryUnavailable ||
            state.usingStaleCache ||
            state.financialObservationUncertain)) {
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
    if (collection == null) {
      final unconfirmed = state.lastSuccessfulSyncAt == null;
      return MissingGroupStateScreen(
        panelTitle: unconfirmed
            ? 'Group not yet confirmed'
            : 'Group not in loaded groups',
        panelMessage: unconfirmed
            ? 'Group information has not been confirmed yet.'
            : 'This group is not in the groups currently loaded.',
      );
    }
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
    final profile = state.currentProfile;
    final session = repo.sessionGeneration;
    final routeGeneration = _routeGeneration;
    final isLive = repo.isLive;
    void joinGroup() => unawaited(
      _joinGroup(
        collection,
        repo,
        profile?.id,
        session,
        routeGeneration,
        isLive,
      ),
    );
    void openContribution() {
      if (!_matchesActionScope(
            collection,
            repo,
            profile?.id,
            session,
            routeGeneration,
            isLive,
          ) ||
          _isJoining(repo, collection.id, profile?.id, session)) {
        return;
      }
      context.go(
        Uri(
          pathSegments: ['', 'groups', collection.id, 'contribute'],
        ).toString(),
      );
    }

    final joiningGroup = _isJoining(repo, collection.id, profile?.id, session);
    final isAdmin = profile != null && collection.creatorUserId == profile.id;
    final canManage =
        isAdmin && !collection.isPlatformSponsored && !collection.isPublic;
    final isMember = isAdmin || collection.isCurrentUserMember;
    final historyQuery = MemberHistoryQuery(collectionId: widget.collectionId);
    // The history RPC is membership-scoped; an empty nonmember response says
    // nothing about whether the group has contributions.
    final history = isMember
        ? ref.watch(memberHistoryProvider(historyQuery))
        : null;
    final visibleContributions =
        history?.page?.items.take(8).toList() ?? const <Contribution>[];
    final hasPaymentRoute = collection.supportsRwandaMomo;
    final paymentEligible =
        collection.contributionRailFor(profile) == 'rwanda_momo';
    final canContribute = paymentEligible && (collection.isPublic || isMember);
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
        eyebrow: ContributionRecordCopy.heroTotalLabel,
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
            '${summary == null ? 'Group total unavailable' : '${ContributionRecordCopy.totalTitle}, $totalLabel'}, '
            '${summary?.supporterCountSemantics ?? 'Contributor count unavailable'}',
        quickActions: [
          if (canContribute)
            CollectHeroQuickAction(
              icon: CollectIcons.donate,
              label: contributionActionLabel,
              onTap: joiningGroup ? null : openContribution,
            ),
          if (isMember)
            CollectHeroQuickAction(
              icon: CollectIcons.people,
              label: 'Members',
              onTap: () => context.go('/groups/${widget.collectionId}/members'),
            ),
          if (isMember || collection.isPublic)
            CollectHeroQuickAction(
              icon: CollectIcons.share,
              label: 'Share',
              onTap: () => context.go('/groups/${widget.collectionId}/share'),
            )
          else
            CollectHeroQuickAction(
              icon: CollectIcons.people,
              label: 'Join',
              onTap: joiningGroup ? null : joinGroup,
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
      bottomAction: collection.isPublic && !isMember
          ? CollectButton(
              key: const ValueKey('join-public-group'),
              label: joiningGroup
                  ? 'Joining group'
                  : profile == null
                  ? isLive
                        ? 'Profile unavailable'
                        : 'Sign in to join'
                  : 'Join group',
              icon: CollectIcons.people,
              onPressed: joiningGroup ? null : joinGroup,
              expand: true,
            )
          : !paymentEligible && isMember
          ? const CollectButton(
              key: ValueKey('group-payment-unavailable'),
              label: 'Payments unavailable',
              icon: CollectIcons.donate,
              onPressed: null,
              expand: true,
            )
          : canManage
          ? null
          : CollectButton(
              label: canContribute
                  ? contributionActionLabel
                  : profile == null
                  ? isLive
                        ? 'Profile unavailable'
                        : 'Sign in to join'
                  : 'Join group',
              icon: canContribute ? CollectIcons.donate : CollectIcons.people,
              onPressed: joiningGroup
                  ? null
                  : canContribute
                  ? openContribution
                  : joinGroup,
              expand: true,
            ),
      children: [
        if (!hasPaymentRoute) ...[
          const InfoSecurityBanner(
            title: 'Payments unavailable',
            message:
                'This group has no in-app payment destination. You can still invite members and view activity.',
            tone: CollectStatusTone.info,
          ),
          CollectSpacing.gap16,
        ] else if (!paymentEligible) ...[
          const InfoSecurityBanner(
            title: 'Payments unavailable',
            message:
                'In-app payments to this group are not supported for your profile. You can still invite members and view activity.',
            tone: CollectStatusTone.info,
          ),
          CollectSpacing.gap16,
        ],
        if (isMember) ...[
          InfoSecurityBanner(
            title: ContributionRecordCopy.ownTotalTitle,
            message: summary == null
                ? 'Not available'
                : '${formatCurrencyTotals(summary.ownBalancesByCurrency)}\n${ContributionRecordCopy.explanation}',
            tone: CollectStatusTone.info,
          ),
          CollectSpacing.gap16,
        ] else ...[
          const InfoSecurityBanner(
            title: ContributionRecordCopy.totalTitle,
            message: ContributionRecordCopy.explanation,
            tone: CollectStatusTone.info,
          ),
          CollectSpacing.gap16,
        ],
        if (!isMember && !collection.isPublic) ...[
          const InfoSecurityBanner(
            title: 'Private group',
            message: 'Use a valid group invitation to join this private group.',
            tone: CollectStatusTone.privacy,
          ),
          CollectSpacing.gap16,
        ],
        const SectionHeader(title: 'Activity'),
        if (!isMember)
          const MinimalStatePanel(
            icon: CollectIcons.activity,
            title: 'Activity for members',
            message: 'Group activity is available to members.',
            tone: CollectStatusTone.privacy,
          )
        else if (history != null && history.loading && history.page == null)
          const Center(child: CircularProgressIndicator())
        else if (history == null || history.page == null)
          CollectDataLoadFailure(
            message: history?.error ?? '',
            onRetry: () => ref
                .read(memberHistoryProvider(historyQuery).notifier)
                .refresh(),
          )
        else if (visibleContributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No contributions yet',
            message: ContributionRecordCopy.emptyMomoMessage,
          )
        else
          _ContributionTimeline(contributions: visibleContributions),
      ],
    );
  }

  Future<void> _joinGroup(
    CollectCollection collection,
    CollectRepository repository,
    String? profileId,
    int session,
    int routeGeneration,
    bool isLive,
  ) async {
    if (!_matchesActionScope(
      collection,
      repository,
      profileId,
      session,
      routeGeneration,
      isLive,
    )) {
      return;
    }
    if (_isJoining(repository, collection.id, profileId, session)) return;
    if (profileId == null) {
      if (isLive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Your profile is unavailable. Refresh and try again.',
            ),
          ),
        );
        return;
      }
      final target = Uri(pathSegments: ['', 'groups', collection.id]);
      context.go(
        Uri(
          path: '/auth',
          queryParameters: {'next': target.toString()},
        ).toString(),
      );
      return;
    }
    final operation = ++_joinOperation;
    bool current() =>
        mounted &&
        operation == _joinOperation &&
        routeGeneration == _routeGeneration &&
        widget.collectionId == collection.id &&
        identical(ref.read(collectRepositoryProvider.notifier), repository) &&
        repository.sessionGeneration == session &&
        repository.isLive == isLive &&
        ref.read(collectRepositoryProvider).currentProfile?.id == profileId;
    try {
      requireMemberGroupProfileReady(ref);
      if (!current()) return;
      setState(() {
        _joiningGroupId = collection.id;
        _joiningProfileId = profileId;
        _joiningSession = session;
        _joiningRepository = repository;
      });
      if (collection.isPublic) {
        await repository.joinPublicGroup(collection.id);
      } else {
        await repository.joinGroupBySlug(collection.slug);
      }
      if (!mounted || !current()) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You joined the group.')));
    } catch (_) {
      if (!mounted || !current()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not confirm joining. Refresh before trying again.',
          ),
        ),
      );
    } finally {
      if (mounted && operation == _joinOperation) {
        setState(() {
          _joiningGroupId = null;
          _joiningProfileId = null;
          _joiningSession = null;
          _joiningRepository = null;
        });
      }
    }
  }
}
