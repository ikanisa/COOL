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
  String _query = '';
  _LedgerSort _sort = _LedgerSort.newest;

  @override
  void dispose() {
    _search.dispose();
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
        avatarTooltip: 'Back',
        searchLabel: 'Search ledger',
        onAvatarTap: () => goBackOrHome(context),
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
      hero: isInitialLoading
          ? null
          : CollectScreenHero(
              eyebrow: collection?.title.toUpperCase() ?? 'LEDGER',
              title: 'Ledger',
              metric: formatRwf(total),
              subtitle: '${contributions.length} confirmed entries',
              icon: CollectIcons.ledger,
              quickActions: [
                CollectHeroQuickAction(
                  icon: CollectIcons.collections,
                  label: 'Group',
                  onTap: () => _showGroupSheet(state.collections),
                ),
                CollectHeroQuickAction(
                  icon: CollectIcons.filter,
                  label: 'Sort',
                  onTap: _showSortSheet,
                ),
                CollectHeroQuickAction(
                  icon: CollectIcons.donate,
                  label: 'Pay',
                  onTap: () =>
                      context.go('/groups/${widget.collectionId}/contribute'),
                ),
                CollectHeroQuickAction(
                  icon: CollectIcons.share,
                  label: 'Share',
                  onTap: () =>
                      context.go('/groups/${widget.collectionId}/share'),
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
              SearchWithClearField(
                controller: _search,
                label: 'Search Collect ID or transaction',
                onChanged: (value) => setState(() => _query = value),
              ),
              _LedgerControlDock(
                groupLabel: collection?.title ?? 'Group',
                sortLabel: _ledgerSortLabel(_sort),
                onGroupTap: () => _showGroupSheet(state.collections),
                onSortTap: _showSortSheet,
              ),
              const SectionHeader(title: 'Activity'),
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

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
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

class _LedgerControlDock extends StatelessWidget {
  const _LedgerControlDock({
    required this.groupLabel,
    required this.sortLabel,
    required this.onGroupTap,
    required this.onSortTap,
  });

  final String groupLabel;
  final String sortLabel;
  final VoidCallback onGroupTap;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LedgerControlButton(
            icon: CollectIcons.collections,
            title: 'Group',
            value: groupLabel,
            onTap: onGroupTap,
          ),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: _LedgerControlButton(
            icon: CollectIcons.activity,
            title: 'Sort',
            value: sortLabel,
            onTap: onSortTap,
          ),
        ),
      ],
    );
  }
}

class _LedgerControlButton extends StatelessWidget {
  const _LedgerControlButton({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      label: '$title $value',
      child: Material(
        color: colors.glassControl,
        borderRadius: CollectRadius.pillBorder,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(color: colors.glassBorder),
          ),
          child: InkWell(
            borderRadius: CollectRadius.pillBorder,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x3,
                vertical: CollectSpacing.x2,
              ),
              child: Row(
                children: [
                  Icon(icon, color: colors.actionColor, size: 20),
                  CollectSpacing.gapW8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: CollectTypography.eyebrowLabel(
                            colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(CollectIcons.chevron, size: 18),
                ],
              ),
            ),
          ),
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
        color: selected ? colors.actionColor : colors.glassControl,
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
                    fontWeight: FontWeight.w900,
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
