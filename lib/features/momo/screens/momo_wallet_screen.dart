import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/transaction_status_chip.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/momo_statement.dart';
import '../providers/momo_statement_providers.dart';
import '../services/momo_statement_export_service.dart';

part 'momo_wallet_parts.dart';

/// Full-page wallet transaction history screen.
///
/// Displays all [MomoWalletEntry] items from the user's `momo_ledger_entries`
/// with date filtering, infinite scroll, and PDF/Excel export.
class MomoWalletScreen extends ConsumerStatefulWidget {
  const MomoWalletScreen({super.key});

  @override
  ConsumerState<MomoWalletScreen> createState() => _MomoWalletScreenState();
}

enum _WalletScopeFilter { all, wallet, groupRelated }

class _MomoWalletScreenState extends ConsumerState<MomoWalletScreen> {
  static const int _baseLimit = 50;

  MomoStatementQuery _query = const MomoStatementQuery(limit: _baseLimit);
  _WalletScopeFilter _scopeFilter = _WalletScopeFilter.all;
  bool _isExportingPdf = false;
  bool _isExportingExcel = false;

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2, 12, 31),
      initialDateRange: _query.startDate == null && _query.endDate == null
          ? null
          : DateTimeRange(
              start: _query.startDate ?? now,
              end: _query.endDate ?? _query.startDate ?? now,
            ),
    );
    if (!mounted || range == null) {
      return;
    }
    setState(() {
      _query = MomoStatementQuery(
        startDate: range.start,
        endDate: range.end,
        limit: _baseLimit,
      );
    });
  }

  void _loadMore() {
    if (!mounted) {
      return;
    }
    setState(() {
      _query = MomoStatementQuery(
        startDate: _query.startDate,
        endDate: _query.endDate,
        limit: _query.limit + _baseLimit,
      );
    });
  }

  Future<void> _export({required StatementExportFormat format}) async {
    final isPdf = format == StatementExportFormat.pdf;
    if (isPdf ? _isExportingPdf : _isExportingExcel) {
      return;
    }

    setState(() {
      if (isPdf) {
        _isExportingPdf = true;
      } else {
        _isExportingExcel = true;
      }
    });

    try {
      final userId = ref.read(authProvider).user?.id;
      if (userId == null || userId.isEmpty) {
        return;
      }

      // Capture l10n values before async gap.
      final l10n = context.l10n;
      final statementTitle = l10n.walletStatementTitle;
      final defaultUserName = l10n.walletDefaultUserName;
      final filterLabel = l10n.walletAllTransactionsFilter;
      final sortLabel = l10n.walletNewestFirst;

      final repository = ref.read(momoStatementRepositoryProvider);
      final exportService = ref.read(momoStatementExportServiceProvider);
      final downloadService = ref.read(momoStatementDownloadServiceProvider);
      final authState = ref.read(authProvider);

      final page = await repository.loadWalletEntriesPage(
        userId,
        query: MomoStatementQuery(
          startDate: _query.startDate,
          endDate: _query.endDate,
          limit: 5000,
        ),
      );

      final export = await exportService.buildWalletExport(
        format: format,
        entries: page.entries,
        metadata: StatementExportMetadata(
          statementTitle: statementTitle,
          fileStem: 'cool_wallet_statement',
          userName: authState.user?.fullName ?? defaultUserName,
          officialPhone:
              authState.user?.officialPhone ?? authState.user?.phone ?? '',
          generatedAt: DateTime.now(),
          periodLabel: _periodLabel(),
          filterLabel: filterLabel,
          sortLabel: sortLabel,
        ),
      );

      await downloadService.saveExport(export);
      if (mounted) {
        CoolToast.success(context, context.l10n.walletStatementExported);
        if (page.entries.length >= 5000 && mounted) {
          CoolToast.info(context, context.l10n.walletExportTruncated(5000));
        }
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, describeUserFacingError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isPdf) {
            _isExportingPdf = false;
          } else {
            _isExportingExcel = false;
          }
        });
      }
    }
  }

  String _periodLabel() {
    final start = _query.startDate;
    final end = _query.endDate;
    if (start == null && end == null) {
      return context.l10n.walletAllInView;
    }
    final startLabel = start == null ? '...' : formatExportDateLabel(start);
    final endLabel = end == null ? '...' : formatExportDateLabel(end);
    return '$startLabel - $endLabel';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    final bundleAsync = ref.watch(momoStatementBundleProvider(_query));

    return CoreDetailScaffold(
      title: Text(
        context.l10n.walletScreenTitle,
        style: context.coolText.displayCondensed(
          Theme.of(context).textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        context.l10n.walletScreenSubtitle,
        style: context.coolText.mono(
          Theme.of(context).textTheme.labelSmall,
          fontWeight: FontWeight.w700,
          color: colors.secondaryText,
          letterSpacing: 1.0,
        ),
      ),
      actions: <Widget>[
        IconButton(
          onPressed: _pickDateRange,
          icon: Icon(
            CoolIcons.calendar,
            color: _query.startDate != null || _query.endDate != null
                ? colors.accent
                : colors.primaryText,
          ),
        ),
        IconButton(
          onPressed: _isExportingPdf
              ? null
              : () => _export(format: StatementExportFormat.pdf),
          icon: _isExportingPdf
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(CoolIcons.pdf, color: colors.primaryText),
        ),
        IconButton(
          onPressed: _isExportingExcel
              ? null
              : () => _export(format: StatementExportFormat.excel),
          icon: _isExportingExcel
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(CoolIcons.grid, color: colors.primaryText),
        ),
        const SizedBox(width: CoolSpace.x2),
      ],
      child: bundleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
          children: [
            _ErrorState(
              colors: colors,
              message: describeUserFacingError(error),
              onRetry: () =>
                  ref.invalidate(momoStatementBundleProvider(_query)),
            ),
          ],
        ),
        data: (bundle) {
          final entries = bundle.walletEntries;
          if (entries.isEmpty) {
            return ListView(
              padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
              children: [_EmptyState(colors)],
            );
          }

          final visibleEntries = entries
              .where(_matchesScopeFilter)
              .toList(growable: false);
          final canLoadMore = entries.length < bundle.walletTotalCount;
          return ListView(
            padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
            children: [
              _WalletScopeFilterBar(
                selected: _scopeFilter,
                onSelected: (value) => setState(() => _scopeFilter = value),
              ),
              const SizedBox(height: CoolSpace.x4),
              if (visibleEntries.isEmpty && !canLoadMore)
                _FilteredEmptyState(scopeFilter: _scopeFilter)
              else
                for (final entry in visibleEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: CoolSpace.x3),
                    child: _WalletTransactionTile(entry: entry),
                  ),
              if (canLoadMore)
                Padding(
                  padding: const EdgeInsets.only(top: CoolSpace.x2),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _loadMore,
                      icon: Icon(
                        CoolIcons.expandCircle,
                        color: colors.accent,
                        size: 20,
                      ),
                      label: Text(
                        context.l10n.walletLoadMore,
                        style: context.coolText.mobiLabel(color: colors.accent),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _matchesScopeFilter(MomoWalletEntry entry) {
    switch (_scopeFilter) {
      case _WalletScopeFilter.all:
        return true;
      case _WalletScopeFilter.wallet:
        return entry.isWalletRelated;
      case _WalletScopeFilter.groupRelated:
        return entry.isGroupRelated;
    }
  }
}
