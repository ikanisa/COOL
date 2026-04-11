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

/// Full-page wallet transaction history screen.
///
/// Displays all [MomoWalletEntry] items from the user's `momo_ledger_entries`
/// with date filtering, infinite scroll, and PDF/Excel export.
class MomoWalletScreen extends ConsumerStatefulWidget {
  const MomoWalletScreen({super.key});

  @override
  ConsumerState<MomoWalletScreen> createState() => _MomoWalletScreenState();
}

class _MomoWalletScreenState extends ConsumerState<MomoWalletScreen> {
  static const int _baseLimit = 50;

  MomoStatementQuery _query = const MomoStatementQuery(limit: _baseLimit);
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

          final canLoadMore = entries.length < bundle.walletTotalCount;
          return ListView.builder(
            padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
            itemCount: entries.length + (canLoadMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == entries.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: CoolSpace.x2),
                  child: Center(
                    child: IconButton(
                      onPressed: _loadMore,
                      icon: Icon(
                        CoolIcons.expandCircle,
                        color: colors.accent,
                        size: 28,
                      ),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: CoolSpace.x3),
                child: _WalletTransactionTile(entry: entries[index]),
              );
            },
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Transaction tile
// ═══════════════════════════════════════════════════════════════

class _WalletTransactionTile extends StatelessWidget {
  const _WalletTransactionTile({required this.entry});

  final MomoWalletEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isCredit = entry.isCredit;
    final amountColor = isCredit ? colors.success : colors.danger;
    final iconColor = isCredit ? colors.success : colors.danger;
    final amountPrefix = isCredit ? '+' : '-';

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Row(
        children: [
          // Direction icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              isCredit
                  ? CoolIcons.arrowDown
                  : CoolIcons.arrowUp,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: CoolSpace.x4),

          // Label + metadata
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.titleSmall,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _buildSubtitle(),
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelSmall,
                    fontWeight: FontWeight.w500,
                    color: colors.secondaryText,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.reference != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.walletRefPrefix(entry.reference!),
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.labelSmall,
                      fontWeight: FontWeight.w500,
                      color: colors.tertiaryText,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CoolSpace.x3),

          // Amount + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$amountPrefix${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                style: context.coolText.mono(
                  Theme.of(context).textTheme.titleSmall,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              TransactionStatusChip(status: entry.ledgerStatus),
            ],
          ),
        ],
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    final counterparty = entry.counterpartyName ?? entry.payerName;
    if (counterparty != null && counterparty.isNotEmpty) {
      parts.add(counterparty);
    }
    parts.add(formatTransactionDate(entry.occurredAt));
    return parts.join(' • ');
  }
}

// ═══════════════════════════════════════════════════════════════
// Empty + Error states
// ═══════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.colors);

  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              CoolIcons.history,
              color: colors.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            context.l10n.walletNoTransactionsYetTitle,
            style: context.coolText.displayCondensed(
              Theme.of(context).textTheme.titleLarge,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            context.l10n.walletNoTransactionsYetMessage,
            textAlign: TextAlign.center,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodySmall,
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.colors, required this.message});

  final CoolSemanticColors colors;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x5),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Text(
        message,
        style: context.coolText.mono(
          Theme.of(context).textTheme.bodyMedium,
          fontWeight: FontWeight.w500,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}
