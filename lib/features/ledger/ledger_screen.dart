import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
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
    final contributions = ref.watch(
      contributionsForCollectionProvider(widget.collectionId),
    );
    final isInitialLoading = state.isLoading && contributions.isEmpty;
    final visible = contributions.where((item) {
      final query = _query.trim().toLowerCase();
      if (query.isEmpty) return true;
      return item.supporterLabel.toLowerCase().contains(query) ||
          (item.transactionId ?? '').toLowerCase().contains(query);
    }).toList()..sort((a, b) => _compareContributions(a, b, _sort));
    final hasAnyLedgerActivity = contributions.isNotEmpty;
    final hasVisibleLedgerActivity = visible.isNotEmpty;
    final total = contributions.fold<int>(
      0,
      (sum, item) => sum + item.amountRwf,
    );

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
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: isInitialLoading
          ? const [
              CollectScreenLoadingState(
                title: 'Loading ledger',
                message: 'Refreshing confirmed contributions.',
                icon: CollectIcons.ledger,
                skeletonCount: 3,
              ),
            ]
          : [
              _LedgerTitleRow(
                groupLabel: collection?.title ?? 'Group',
                total: total,
                count: contributions.length,
              ),
              if (_searching)
                SearchWithClearField(
                  controller: _search,
                  focusNode: _searchFocus,
                  label: 'Search Collect ID or transaction',
                  onChanged: (value) => setState(() => _query = value),
                ),
              if (!hasAnyLedgerActivity)
                EmptyIllustrationState(
                  icon: CollectIcons.ledger,
                  title: 'No ledger activity',
                  message:
                      'Confirmed MoMo contributions will appear here after SMS verification.',
                  action: CollectButton(
                    label: 'Contribute now',
                    icon: CollectIcons.momo,
                    onPressed: () =>
                        context.go('/groups/${widget.collectionId}/contribute'),
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
                )
              else
                CollectCard(
                  emphasis: CollectCardEmphasis.flat,
                  child: Column(
                    children: [
                      for (final contribution in visible)
                        FinancialListRow(
                          title: compactCollectIdLabel(
                            contribution.supporterLabel,
                          ),
                          amountRwf: contribution.amountRwf,
                          meta: formatCollectDateTime(contribution.createdAt),
                          transactionId: contribution.transactionId,
                          leading: CollectIcons.ledger,
                        ),
                    ],
                  ),
                ),
            ],
    );
  }

  void _showGroupSheet(List<CollectCollection> collections) {
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
    required this.total,
    required this.count,
  });

  final String groupLabel;
  final int total;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final stackAmount =
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
          formatRwf(total),
          style: CollectTypography.amountLarge(colors.textPrimary),
          maxLines: 1,
        ),
      ),
    );
    return Semantics(
      container: true,
      header: true,
      label:
          '$groupLabel ledger, ${formatRwf(total)}, $count confirmed entries',
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
                      formatRwf(total),
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
    _LedgerSort.highest => 'Highest',
    _LedgerSort.lowest => 'Lowest',
  };
}

int _compareContributions(
  Contribution left,
  Contribution right,
  _LedgerSort sort,
) {
  return switch (sort) {
    _LedgerSort.newest => right.createdAt.compareTo(left.createdAt),
    _LedgerSort.oldest => left.createdAt.compareTo(right.createdAt),
    _LedgerSort.highest => right.amountRwf.compareTo(left.amountRwf),
    _LedgerSort.lowest => left.amountRwf.compareTo(right.amountRwf),
  };
}

String _emptyTitleForFilter() => 'No transactions found';

String _emptyMessageForFilter() =>
    'No contribution matches that Collect ID or transaction reference.';
