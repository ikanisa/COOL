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
    }).toList();
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
        PremiumSegmentedFilter<_LedgerFilter>(
          values: _LedgerFilter.values,
          selected: _filter,
          labelFor: _ledgerFilterLabel,
          onChanged: (filter) => setState(() => _filter = filter),
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
                    meta: 'Intent ${intent.id}',
                    subtitle: intent.receiverLabel,
                    transactionId: intent.id,
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
}

enum _LedgerFilter { all, confirmed, pending, review, mine }

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
      'Payment intents waiting for MoMo SMS verification will appear here.',
    _LedgerFilter.review =>
      'Payments that need support review will appear here without exposing public raw SMS details.',
    _LedgerFilter.mine =>
      'No contribution from your Collect ID matches the current search.',
    _ =>
      'No confirmed contribution matches that Collect ID or transaction reference.',
  };
}
