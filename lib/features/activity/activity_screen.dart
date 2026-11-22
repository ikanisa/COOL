import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/models/contribution_record_copy.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_data_load_failure.dart';
import '../../shared/widgets/collect_history_footer.dart';
import '../../shared/widgets/screen_scaffold.dart';
import '../history/member_history_refresh.dart';

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(memberGroupSessionProvider);
    return _ActivityView(key: ValueKey(owner), owner: owner);
  }
}

class _ActivityView extends ConsumerStatefulWidget {
  const _ActivityView({required this.owner, super.key});
  final MemberGroupSession owner;

  @override
  ConsumerState<_ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends ConsumerState<_ActivityView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String? _collectionId;
  bool _searching = false;

  MemberHistoryQuery get _visibleQuery => MemberHistoryQuery(
    collectionId: _collectionId,
    search: _search.text.trim().toLowerCase(),
  );

  bool get _ownsSession =>
      mounted &&
      identical(
        ref.read(memberGroupRepositoryProvider),
        widget.owner.repository,
      ) &&
      widget.owner.repository.sessionGeneration == widget.owner.generation &&
      ref.read(memberGroupAccessStateProvider).currentProfile?.id ==
          widget.owner.profileId;

  Future<void> _refreshHistory(MemberHistoryQuery query) =>
      refreshMemberHistory(
        ref: ref,
        session: widget.owner,
        query: query,
        isCurrent: () => _ownsSession && query == _visibleQuery,
      );

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memberGroupDirectoryStateProvider);
    final collectionsById = {
      for (final collection in state.collections) collection.id: collection,
    };
    final query = _visibleQuery;
    final provider = ref.watch(memberHistoryQueriesProvider)(query);
    final feed = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final visible = feed.page?.items ?? const <Contribution>[];
    final total = feed.page == null
        ? 'Not available'
        : formatCurrencyTotals(feed.page!.totals, separator: '\n');
    final isInitialLoading =
        (feed.loading && feed.page == null) ||
        (state.isLoading &&
            state.collections.isEmpty &&
            !state.hasRecordedContributions);

    return ScreenScaffold(
      title: 'Activity',
      showHeader: false,
      compact: true,
      topChrome: CollectScreenTopChrome(
        avatarLabel: state.currentProfile?.publicId,
        avatarTooltip: 'Profile',
        searchLabel: 'Search activity',
        onAvatarTap: () => context.go('/settings'),
        onSearchTap: _beginSearch,
        actions: [
          CollectChromeAction(
            icon: CollectIcons.filter,
            tooltip: _collectionId == null ? 'Filter by group' : 'Group filter',
            onPressed: _showGroupFilter,
          ),
        ],
      ),
      onRefresh: () => _refreshHistory(query),
      sliver: isInitialLoading || state.hasInitialLoadFailure || visible.isEmpty
          ? null
          : SliverMainAxisGroup(
              slivers: [
                CollectSliverCardList(
                  topSpacing: CollectSpacing.x3,
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final contribution = visible[index];
                    return ActivityFeedItem(
                      key: ValueKey(contribution.id),
                      title:
                          contribution.groupTitle ??
                          collectionsById[contribution.collectionId]?.title ??
                          'Group contribution',
                      amount: contribution.amountRwf,
                      currency: contribution.currency,
                      meta:
                          '${ContributionRecordCopy.labelFor(contribution)} · '
                          '${compactCollectIdLabel(contribution.supporterLabel)}'
                          ' · ${formatCollectDateTime(contribution.createdAt)}',
                      transactionId: contribution.transactionId,
                      tone: contribution.isCompensation
                          ? CollectStatusTone.warning
                          : CollectStatusTone.info,
                      prioritizeContext: true,
                      onTap: () => context.go(
                        '/groups/${contribution.collectionId}/ledger',
                      ),
                    );
                  },
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 56,
                    color: context.collectColors.border.withValues(alpha: 0.48),
                  ),
                ),
                SliverToBoxAdapter(
                  child: CollectHistoryFooter(
                    feed: feed,
                    onMore: controller.loadMore,
                    onRefresh: controller.refresh,
                  ),
                ),
              ],
            ),
      children: [
        if (_searching)
          SearchWithClearField(
            controller: _search,
            focusNode: _searchFocus,
            label: 'Search group, Collect ID, or transaction',
            onChanged: (_) => setState(() {}),
          ),
        ...(isInitialLoading
            ? const [
                CollectScreenLoadingState(
                  title: 'Loading activity',
                  message: ContributionRecordCopy.loadingMessage,
                  icon: CollectIcons.activity,
                  skeletonCount: 3,
                ),
              ]
            : state.hasInitialLoadFailure || feed.page == null
            ? [
                CollectDataLoadFailure(
                  message: feed.error ?? '',
                  onRetry: () => _refreshHistory(query),
                ),
              ]
            : [
                _ActivityTitleRow(
                  total: total,
                  count: feed.page?.totalCount ?? 0,
                  groupLabel: _selectedGroupLabel(collectionsById),
                  signedHistory: feed.page?.isSignedHistory ?? false,
                ),
                InfoSecurityBanner(
                  title: feed.page?.isSignedHistory == true
                      ? ContributionRecordCopy.netTotalTitle
                      : ContributionRecordCopy.totalTitle,
                  message: ContributionRecordCopy.explanation,
                  tone: CollectStatusTone.info,
                ),
                if (visible.isEmpty && query.isDefault)
                  const EmptyIllustrationState(
                    icon: CollectIcons.activity,
                    title: 'No activity yet',
                    message: ContributionRecordCopy.emptyMomoMessage,
                  )
                else if (visible.isEmpty)
                  EmptySearchState(
                    title: 'No matching activity',
                    message: 'Clear the search or group filter and try again.',
                    onClear: _clearFilters,
                  ),
              ]),
      ],
    );
  }

  String _selectedGroupLabel(Map<String, CollectCollection> collectionsById) {
    final selected = _collectionId;
    if (selected == null) return 'All groups';
    return collectionsById[selected]?.title ?? 'Selected group';
  }

  void _beginSearch() {
    if (!_searching) {
      setState(() => _searching = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _collectionId = null;
    });
  }

  void _showGroupFilter() {
    if (!_ownsSession) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final sheetState = sheetRef.watch(memberGroupAccessStateProvider);
          sheetRef.watch(memberGroupRepositoryProvider);
          final available = _ownsSession && !sheetState.memberScopeUncertain;
          return CollectBottomSheet(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(title: 'Filter by group'),
                  if (!available) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _ownsSession
                            ? 'Group information is unavailable. Close and refresh your data.'
                            : 'Account changed. Close and reopen this filter.',
                      ),
                    ),
                    CollectSpacing.gap12,
                    CollectButton(
                      label: 'Close',
                      variant: CollectButtonVariant.secondary,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      expand: true,
                    ),
                  ] else
                    RadioGroup<String?>(
                      groupValue: _collectionId,
                      onChanged: (value) {
                        if (!_ownsSession) return;
                        final latest = ref.read(memberGroupAccessStateProvider);
                        if (latest.memberScopeUncertain ||
                            (value != null &&
                                !latest.collections.any(
                                  (group) => group.id == value,
                                ))) {
                          return;
                        }
                        setState(() => _collectionId = value);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Column(
                        children: [
                          const RadioListTile<String?>(
                            value: null,
                            title: Text('All groups'),
                          ),
                          for (final collection in sheetState.collections)
                            RadioListTile<String?>(
                              value: collection.id,
                              title: Text(collection.title),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActivityTitleRow extends StatelessWidget {
  const _ActivityTitleRow({
    required this.total,
    required this.count,
    required this.groupLabel,
    this.signedHistory = false,
  });

  final String total;
  final int count;
  final String groupLabel;
  final bool signedHistory;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.textPrimary;
    final muted = colors.textSecondary;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activity',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: foreground,
            fontWeight: CollectTypography.weightBold,
            letterSpacing: CollectTypography.trackingDefault,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$groupLabel · $count',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: CollectTypography.weightSemibold,
                ),
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            CollectSpacing.gap4,
            Icon(CollectIcons.ledger, size: 14, color: muted),
          ],
        ),
      ],
    );
    final amount = Text(
      total,
      style: CollectTypography.amountCompact(foreground),
    );
    return Semantics(
      header: true,
      label:
          'Activity, $groupLabel, ${ContributionRecordCopy.countLabel(count, signedHistory: signedHistory)}, $total',
      child: ExcludeSemantics(
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, CollectSpacing.gap8, amount],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  amount,
                ],
              ),
      ),
    );
  }
}
