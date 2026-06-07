import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
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
  _LedgerFilter _filter = _LedgerFilter.all;
  _LedgerSort _sort = _LedgerSort.newest;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final profile = state.currentProfile;
    final contributions = ref.watch(
      contributionsForCollectionProvider(widget.collectionId),
    );
    final pendingIntents = state.paymentIntents
        .where(
          (item) =>
              item.collectionId == widget.collectionId &&
              paymentStatusTone(item.status) != CollectStatusTone.success,
        )
        .toList();
    final filteredContributions = switch (_filter) {
      _LedgerFilter.all || _LedgerFilter.confirmed => contributions,
      _LedgerFilter.mine => [
        for (final item in contributions)
          if (profile != null &&
              (item.supporterLabel.contains(profile.publicId) ||
                  item.supporterLabel == profile.safeAlias))
            item,
      ],
      _LedgerFilter.pending || _LedgerFilter.review => <Contribution>[],
    };
    final visible = filteredContributions.where((item) {
      final query = _query.trim().toLowerCase();
      if (query.isEmpty) return true;
      return item.supporterLabel.toLowerCase().contains(query) ||
          (item.transactionId ?? '').toLowerCase().contains(query);
    }).toList()..sort((a, b) => _compareContributions(a, b, _sort));
    final visiblePending =
        pendingIntents.where((item) {
          final query = _query.trim().toLowerCase();
          final matchesStatus = switch (_filter) {
            _LedgerFilter.all => true,
            _LedgerFilter.pending => _isPendingStatus(item.status),
            _LedgerFilter.review => _isReviewStatus(item.status),
            _LedgerFilter.confirmed || _LedgerFilter.mine => false,
          };
          if (!matchesStatus) return false;
          if (query.isEmpty) return true;
          return item.id.toLowerCase().contains(query) ||
              item.receiverLabel.toLowerCase().contains(query) ||
              paymentStatusLabel(item.status).toLowerCase().contains(query);
        }).toList()..sort((a, b) {
          final statusSort = _ledgerIntentSort(
            a.status,
          ).compareTo(_ledgerIntentSort(b.status));
          if (statusSort != 0) return statusSort;
          return b.createdAt.compareTo(a.createdAt);
        });
    final hasAnyLedgerActivity =
        contributions.isNotEmpty || pendingIntents.isNotEmpty;
    final hasVisibleLedgerActivity =
        visible.isNotEmpty || visiblePending.isNotEmpty;
    final total = contributions.fold<int>(
      0,
      (sum, item) => sum + item.amountRwf,
    );

    return ScreenScaffold(
      title: 'Ledger',
      children: [
        MoneyHeroCard(
          amount: total,
          label: 'Confirmed ledger',
          detail: '${contributions.length} entries',
        ),
        SearchWithClearField(
          controller: _search,
          label: 'Search Collect ID or transaction',
          onChanged: (value) => setState(() => _query = value),
        ),
        _LedgerFilterRail(
          selected: _filter,
          onChanged: (filter) => setState(() => _filter = filter),
        ),
        SectionHeader(
          title: 'Activity',
          actionLabel: _ledgerSortLabel(_sort),
          onAction: _showSortSheet,
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
            title: _emptyTitleForFilter(_filter),
            message: _emptyMessageForFilter(_filter),
            onClear: () => setState(() {
              _search.clear();
              _query = '';
              _filter = _LedgerFilter.all;
            }),
          )
        else
          CollectCard(
            emphasis: CollectCardEmphasis.flat,
            child: Column(
              children: [
                for (final intent in visiblePending)
                  FinancialListRow(
                    title: paymentStatusLabel(intent.status),
                    amountRwf: intent.expectedAmountRwf,
                    meta: 'Awaiting MoMo confirmation',
                    subtitle: intent.receiverLabel,
                    leading: CollectIcons.pending,
                    tone: paymentStatusTone(intent.status),
                  ),
                for (final contribution in visible)
                  FinancialListRow(
                    title: compactCollectIdLabel(contribution.supporterLabel),
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

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sort activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              CollectSpacing.gap12,
              for (final sort in _LedgerSort.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _sort == sort ? CollectIcons.check : CollectIcons.filter,
                  ),
                  title: Text(_ledgerSortLabel(sort)),
                  onTap: () {
                    setState(() => _sort = sort);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LedgerFilterRail extends StatelessWidget {
  const _LedgerFilterRail({required this.selected, required this.onChanged});

  final _LedgerFilter selected;
  final ValueChanged<_LedgerFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: _LedgerFilter.values.length,
        separatorBuilder: (_, _) => CollectSpacing.gapW8,
        itemBuilder: (context, index) {
          final filter = _LedgerFilter.values[index];
          return _LedgerFilterChip(
            label: _ledgerFilterLabel(filter),
            selected: selected == filter,
            onTap: () => onChanged(filter),
          );
        },
      ),
    );
  }
}

class _LedgerFilterChip extends StatelessWidget {
  const _LedgerFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? colors.actionCrimson : colors.surfaceRaised,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x4,
              vertical: CollectSpacing.x2,
            ),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected ? Colors.white : colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _LedgerFilter { all, confirmed, pending, review, mine }

enum _LedgerSort { newest, oldest, highest, lowest }

bool _isPendingStatus(String status) => status == 'pending';

bool _isReviewStatus(String status) {
  return status == 'needs_review' || status == 'review';
}

int _ledgerIntentSort(String status) {
  if (_isReviewStatus(status)) return 0;
  if (_isPendingStatus(status)) return 1;
  return 2;
}

String _ledgerFilterLabel(_LedgerFilter filter) {
  return switch (filter) {
    _LedgerFilter.all => 'All',
    _LedgerFilter.confirmed => 'Confirmed',
    _LedgerFilter.pending => 'Pending',
    _LedgerFilter.review => 'Needs review',
    _LedgerFilter.mine => 'Mine',
  };
}

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

String _emptyTitleForFilter(_LedgerFilter filter) {
  return switch (filter) {
    _LedgerFilter.pending => 'No pending payments',
    _LedgerFilter.review => 'No review items',
    _LedgerFilter.mine => 'No matching contributions',
    _ => 'No transactions found',
  };
}

String _emptyMessageForFilter(_LedgerFilter filter) {
  return switch (filter) {
    _LedgerFilter.pending =>
      'Payments waiting for MoMo SMS verification will appear here.',
    _LedgerFilter.review =>
      'Payments that need support review will appear here without exposing public raw SMS details.',
    _LedgerFilter.mine =>
      'No contribution from your Collect ID matches the current search.',
    _ =>
      'No confirmed contribution matches that Collect ID or transaction reference.',
  };
}
