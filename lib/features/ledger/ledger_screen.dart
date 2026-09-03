import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_data_load_failure.dart';
import '../../shared/widgets/collect_history_footer.dart';
import '../../shared/widgets/screen_scaffold.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  _LedgerSort _sort = _LedgerSort.newest;
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    final summary = repo.summaryFor(widget.collectionId);
    final query = MemberHistoryQuery(
      collectionId: widget.collectionId,
      search: _query.trim().toLowerCase(),
      sort: _sort.name,
    );
    final feed = ref.watch(memberHistoryProvider(query));
    final controller = ref.read(memberHistoryProvider(query).notifier);
    final visible = feed.page?.items ?? const <Contribution>[];
    final isInitialLoading =
        (feed.loading && feed.page == null) ||
        (state.isLoading && feed.page == null);
    final hasAnyLedgerActivity = visible.isNotEmpty || _query.isNotEmpty;
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
              onPressed: () => _showGroupSheet(state.collections),
            ),
          CollectChromeAction(
            icon: CollectIcons.filter,
            tooltip: 'Sort ledger',
            onPressed: _showSortSheet,
          ),
        ],
      ),
      onRefresh: () async {
        await ref.read(collectRepositoryProvider.notifier).loadInitial();
        if (mounted) {
          await ref.read(memberHistoryProvider(query).notifier).refresh();
        }
      },
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
                    );
                  },
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
            label: 'Search Collect ID or transaction',
            onChanged: (value) => setState(() => _query = value),
          ),
        ...(isInitialLoading
            ? const [
                CollectScreenLoadingState(
                  title: 'Loading ledger',
                  message: 'Refreshing confirmed contributions.',
                  icon: CollectIcons.ledger,
                  skeletonCount: 3,
                ),
              ]
            : state.hasInitialLoadFailure ||
                  (feed.error != null && feed.page == null)
            ? [
                CollectDataLoadFailure(
                  onRetry: () async {
                    await ref
                        .read(collectRepositoryProvider.notifier)
                        .loadInitial();
                    if (mounted) {
                      await ref
                          .read(memberHistoryProvider(query).notifier)
                          .refresh();
                    }
                  },
                ),
              ]
            : [
                _LedgerTitleRow(
                  groupLabel: collection?.title ?? 'Group',
                  totals: summary.totalsByCurrency,
                  count: feed.page?.totalCount ?? 0,
                ),
                InfoSecurityBanner(
                  title: 'Your confirmed balance',
                  message:
                      'You have ${formatCurrencyTotals(summary.ownBalancesByCurrency)} in confirmed contributions.',
                  tone: CollectStatusTone.info,
                ),
                if (!hasAnyLedgerActivity)
                  EmptyIllustrationState(
                    icon: CollectIcons.ledger,
                    title: 'No ledger activity',
                    message: collection?.supportsRwandaMomo == true
                        ? 'Confirmed MoMo contributions appear here.'
                        : 'Bank contributions appear here only after daily statement reconciliation.',
                    action: CollectButton(
                      label: 'Contribute now',
                      icon: CollectIcons.bank,
                      onPressed: () => context.go(
                        '/groups/${widget.collectionId}/contribute',
                      ),
                    ),
                  )
                else if (!hasVisibleLedgerActivity)
                  EmptySearchState(
                    title: _emptyTitleForFilter(),
                    message: _emptyMessageForFilter(),
                    onClear: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
              ]),
      ],
    );
  }

  void _showGroupSheet(List<CollectCollection> collections) {
    if (collections.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: CollectMotion.animationStyle(context),
      builder: (context) {
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
              Navigator.of(context).pop();
              if (collection.id != widget.collectionId) {
                context.go('/groups/${collection.id}/ledger');
              }
            },
          ),
        );
      },
    );
  }

  void _beginSearch() {
    if (!_searching) {
      setState(() => _searching = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _showSortSheet() {
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
              setState(() => _sort = sort);
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
  });

  final String groupLabel;
  final Map<String, int> totals;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final stackAmount =
        totals.length > 1 ||
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
          formatCurrencyTotals(totals, separator: '\n'),
          style: CollectTypography.amountLarge(colors.textPrimary),
          maxLines: totals.length.clamp(1, 2),
        ),
      ),
    );
    return Semantics(
      container: true,
      header: true,
      label:
          '$groupLabel ledger, ${formatCurrencyTotals(totals)}, $count confirmed entries',
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
                      formatCurrencyTotals(totals),
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
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colors.selectedOnAccent
                        : colors.textPrimary,
                    fontWeight: CollectTypography.weightSemibold,
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
