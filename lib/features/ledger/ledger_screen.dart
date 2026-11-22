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

class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({
    required this.collectionId,
    this.initialPaymentId,
    super.key,
  });

  final String collectionId;
  final String? initialPaymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(memberGroupSessionProvider);
    return _LedgerView(
      key: ValueKey(session),
      session: session,
      collectionId: collectionId,
      initialPaymentId: initialPaymentId,
    );
  }
}

class _LedgerView extends ConsumerStatefulWidget {
  const _LedgerView({
    required this.session,
    required this.collectionId,
    required this.initialPaymentId,
    super.key,
  });

  final MemberGroupSession session;
  final String collectionId;
  final String? initialPaymentId;

  @override
  ConsumerState<_LedgerView> createState() => _LedgerViewState();
}

class _LedgerViewState extends ConsumerState<_LedgerView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  _LedgerSort _sort = _LedgerSort.newest;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _applyPaymentContext();
  }

  void _applyPaymentContext() {
    final paymentId = widget.initialPaymentId;
    if (paymentId != null && paymentId.isNotEmpty) {
      _search.text = paymentId;
      _searching = true;
    } else {
      _search.clear();
      _searching = false;
    }
  }

  @override
  void didUpdateWidget(_LedgerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionId != widget.collectionId ||
        oldWidget.initialPaymentId != widget.initialPaymentId) {
      _applyPaymentContext();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  MemberHistoryQuery get _visibleQuery => MemberHistoryQuery(
    collectionId: widget.collectionId,
    search: _search.text.trim().toLowerCase(),
    sort: _sort.name,
  );

  bool get _ownsSession =>
      mounted &&
      ref.read(memberGroupSessionProvider) == widget.session &&
      widget.session.repository.sessionGeneration == widget.session.generation;

  bool _showsQuery(MemberHistoryQuery query) =>
      _ownsSession && query == _visibleQuery;

  Future<void> _refreshHistory(MemberHistoryQuery query) =>
      refreshMemberHistory(
        ref: ref,
        session: widget.session,
        query: query,
        isCurrent: () => _showsQuery(query),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(memberGroupDirectoryStateProvider);
    final repo = widget.session.repository;
    final collection = repo.maybeCollectionById(widget.collectionId);
    final summary = repo.summaryFor(widget.collectionId);
    final query = _visibleQuery;
    final history = ref.watch(memberHistoryQueriesProvider)(query);
    final feed = ref.watch(history);
    final controller = ref.read(history.notifier);
    final visible = feed.page?.items ?? const <Contribution>[];
    final isInitialLoading =
        (feed.loading && feed.page == null) ||
        (state.isLoading && feed.page == null);
    final hasAnyLedgerActivity = visible.isNotEmpty || _search.text.isNotEmpty;
    final hasVisibleLedgerActivity = visible.isNotEmpty;

    return ScreenScaffold(
      title: 'Ledger',
      showHeader: false,
      compact: true,
      topChrome: CollectScreenTopChrome(
        avatarIcon: CollectIcons.back,
        avatarTooltip: 'Back',
        searchLabel: 'Search',
        onAvatarTap: () => goBackOrHome(context),
        onSearchTap: _beginSearch,
        actions: [
          if (state.collections.isNotEmpty)
            CollectChromeAction(
              icon: CollectIcons.collections,
              tooltip: 'Filter by group',
              onPressed: _showGroupSheet,
            ),
          CollectChromeAction(
            icon: CollectIcons.filter,
            tooltip: 'Sort ledger',
            onPressed: _showSortSheet,
          ),
        ],
      ),
      onRefresh: () => _refreshHistory(query),
      sliver: isInitialLoading || visible.isEmpty
          ? null
          : SliverMainAxisGroup(
              slivers: [
                CollectSliverCardList(
                  topSpacing: CollectSpacing.x3,
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final contribution = visible[index];
                    return FinancialListRow(
                      key: ValueKey(contribution.id),
                      title: compactCollectIdLabel(contribution.supporterLabel),
                      amountRwf: contribution.amountRwf,
                      currency: contribution.currency,
                      meta: formatCollectDateTime(contribution.createdAt),
                      transactionId: contribution.transactionId,
                      leading: CollectIcons.ledger,
                      subtitle: ContributionRecordCopy.labelFor(contribution),
                      tone: contribution.isCompensation
                          ? CollectStatusTone.warning
                          : CollectStatusTone.info,
                    );
                  },
                ),
                SliverToBoxAdapter(
                  child: CollectHistoryFooter(
                    feed: feed,
                    onMore: () {
                      if (_showsQuery(query)) controller.loadMore();
                    },
                    onRefresh: () {
                      if (_showsQuery(query)) controller.refresh();
                    },
                  ),
                ),
              ],
            ),
      children: [
        if (_searching)
          SearchWithClearField(
            controller: _search,
            focusNode: _searchFocus,
            label: 'Search Collect ID or transaction',
            onChanged: (_) => setState(() {}),
          ),
        ...(isInitialLoading
            ? const [
                CollectScreenLoadingState(
                  title: 'Loading ledger',
                  message: ContributionRecordCopy.loadingMessage,
                  icon: CollectIcons.ledger,
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
                _LedgerTitleRow(
                  groupLabel: collection?.title ?? 'Group',
                  totals: feed.page?.isSignedHistory == true
                      ? feed.page?.totals
                      : summary?.totalsByCurrency,
                  count: feed.page?.totalCount ?? 0,
                  signedHistory: feed.page?.isSignedHistory ?? false,
                ),
                InfoSecurityBanner(
                  title: feed.page?.isSignedHistory == true
                      ? ContributionRecordCopy.ownNetTotalTitle
                      : ContributionRecordCopy.ownTotalTitle,
                  message: feed.page?.isSignedHistory == true
                      ? '${formatCurrencyTotals(feed.page!.ownTotals)}\n${ContributionRecordCopy.explanation}'
                      : summary == null
                      ? 'Not available'
                      : '${formatCurrencyTotals(summary.ownBalancesByCurrency)}\n${ContributionRecordCopy.explanation}',
                  tone: CollectStatusTone.info,
                ),
                if (!hasAnyLedgerActivity)
                  EmptyIllustrationState(
                    icon: CollectIcons.ledger,
                    title: 'No ledger activity',
                    message: collection?.supportsRwandaMomo == true
                        ? ContributionRecordCopy.emptyMomoMessage
                        : 'This group does not have an active MoMo contribution route.',
                    action: collection?.supportsRwandaMomo == true
                        ? CollectButton(
                            label: 'Contribute now',
                            icon: CollectIcons.momo,
                            onPressed: () => context.go(
                              '/groups/${widget.collectionId}/contribute',
                            ),
                          )
                        : null,
                  )
                else if (!hasVisibleLedgerActivity)
                  EmptySearchState(
                    title: _emptyTitleForFilter(),
                    message: _emptyMessageForFilter(),
                    onClear: () => setState(_search.clear),
                  ),
              ]),
      ],
    );
  }

  void _showGroupSheet() {
    final groupId = widget.collectionId;
    bool current() => _ownsSession && groupId == widget.collectionId;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (context) => Consumer(
        builder: (context, sheetRef, _) {
          final sheetState = sheetRef.watch(memberGroupAccessStateProvider);
          sheetRef.watch(memberGroupSessionProvider);
          final collections = sheetState.collections;
          if (!current() ||
              sheetState.memberScopeUncertain ||
              collections.isEmpty) {
            return CollectBottomSheet(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      !current()
                          ? 'Account changed. Close and reopen this filter.'
                          : sheetState.memberScopeUncertain
                          ? 'Group information is unavailable. Close and refresh your data.'
                          : sheetState.isLoading
                          ? 'Refreshing groups.'
                          : 'No groups are available for this filter.',
                    ),
                  ),
                  CollectSpacing.gap12,
                  CollectButton(
                    label: 'Close',
                    variant: CollectButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                    expand: true,
                  ),
                ],
              ),
            );
          }
          return CollectBottomSheet(
            child: _LedgerOptionSheet<CollectCollection>(
              title: 'Filter by group',
              values: collections,
              selected: collections.firstWhere(
                (item) => item.id == widget.collectionId,
                orElse: () => collections.first,
              ),
              labelFor: (collection) => collection.title,
              onSelected: (collection) {
                if (!current()) return;
                final latest = ref.read(memberGroupAccessStateProvider);
                if (latest.memberScopeUncertain ||
                    !latest.collections.any(
                      (group) => group.id == collection.id,
                    )) {
                  return;
                }
                Navigator.of(context).pop();
                if (collection.id != widget.collectionId) {
                  context.go('/groups/${collection.id}/ledger');
                }
              },
            ),
          );
        },
      ),
    );
  }

  void _beginSearch() {
    if (!_searching) {
      setState(() => _searching = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ownsSession) _searchFocus.requestFocus();
    });
  }

  void _showSortSheet() {
    final groupId = widget.collectionId;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (context) {
        return CollectBottomSheet(
          child: _LedgerOptionSheet<_LedgerSort>(
            title: 'Sort ledger',
            values: _LedgerSort.values,
            selected: _sort,
            labelFor: _ledgerSortLabel,
            onSelected: (sort) {
              if (_ownsSession && groupId == widget.collectionId) {
                setState(() => _sort = sort);
              }
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }
}

class _LedgerTitleRow extends StatelessWidget {
  const _LedgerTitleRow({
    required this.groupLabel,
    required this.totals,
    required this.count,
    this.signedHistory = false,
  });

  final String groupLabel;
  final Map<String, int>? totals;
  final int count;
  final bool signedHistory;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final amountLabel = totals == null
        ? 'Not available'
        : formatCurrencyTotals(totals!, separator: '\n');
    final stackAmount =
        (totals?.length ?? 0) > 1 ||
        MediaQuery.sizeOf(context).width < 390 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final title = Text(
      'Ledger',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        color: colors.textPrimary,
        fontWeight: CollectTypography.weightBold,
        letterSpacing: CollectTypography.trackingDefault,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final amount = SizedBox(
      width: double.infinity,
      child: FittedBox(
        alignment: Alignment.centerLeft,
        fit: BoxFit.scaleDown,
        child: Text(
          amountLabel,
          style: CollectTypography.amountLarge(colors.textPrimary),
          maxLines: (totals?.length ?? 1).clamp(1, 2),
        ),
      ),
    );
    return Semantics(
      container: true,
      header: true,
      label:
          '$groupLabel ledger, '
          '${totals == null ? 'Group total unavailable' : formatCurrencyTotals(totals!)}, '
          '${ContributionRecordCopy.countLabel(count, signedHistory: signedHistory)}',
      child: ExcludeSemantics(
        child: stackAmount
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, CollectSpacing.gap8, amount],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  CollectSpacing.gapW12,
                  Flexible(
                    child: Text(
                      amountLabel,
                      style: CollectTypography.amountLarge(colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _LedgerOptionSheet<T> extends StatelessWidget {
  const _LedgerOptionSheet({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          CollectSpacing.gap12,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              for (final value in values)
                _LedgerSheetPill<T>(
                  value: value,
                  label: labelFor(value),
                  selected: selected == value,
                  onSelected: onSelected,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LedgerSheetPill<T> extends StatelessWidget {
  const _LedgerSheetPill({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final T value;
  final String label;
  final bool selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter option $label',
      child: Material(
        color: selected ? colors.actionColor : colors.controlSurface,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: () => onSelected(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x3,
              vertical: CollectSpacing.x2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? CollectIcons.check : CollectIcons.filter,
                  size: 18,
                  color: selected
                      ? colors.selectedOnAccent
                      : colors.textSecondary,
                ),
                CollectSpacing.gapW8,
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? colors.selectedOnAccent
                          : colors.textPrimary,
                      fontWeight: CollectTypography.weightSemibold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _LedgerSort { newest, oldest, highest, lowest }

String _ledgerSortLabel(_LedgerSort sort) {
  return switch (sort) {
    _LedgerSort.newest => 'Newest',
    _LedgerSort.oldest => 'Oldest',
    _LedgerSort.highest => 'Highest by currency',
    _LedgerSort.lowest => 'Lowest by currency',
  };
}

String _emptyTitleForFilter() => 'No transactions found';

String _emptyMessageForFilter() =>
    'No contribution matches that Collect ID or transaction reference.';
