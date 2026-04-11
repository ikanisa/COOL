import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_icons.dart';
import '../../../core/utils/date_formatters.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/transaction_status_chip.dart';
import '../../auth/providers/auth_provider.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../../momo/services/momo_statement_export_service.dart';
import '../providers/groups_provider.dart';
import '../widgets/transaction_allocation_sheet.dart';

/// Full-page statements screen filtered to a specific group.
class GroupStatementsScreen extends ConsumerStatefulWidget {
  const GroupStatementsScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupStatementsScreen> createState() =>
      _GroupStatementsScreenState();
}

class _GroupStatementsScreenState extends ConsumerState<GroupStatementsScreen> {
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

  Future<void> _export({
    required StatementExportFormat format,
    required String groupName,
  }) async {
    final isPdf = format == StatementExportFormat.pdf;
    final l10n = context.l10n;
    final periodLabel = _periodLabel();
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
      final repository = ref.read(momoStatementRepositoryProvider);
      final exportService = ref.read(momoStatementExportServiceProvider);
      final downloadService = ref.read(momoStatementDownloadServiceProvider);
      final authState = ref.read(authProvider);

      final page = await repository.loadGroupPaymentLedgerEntriesPage(
        widget.groupId,
        query: MomoStatementQuery(
          startDate: _query.startDate,
          endDate: _query.endDate,
          limit: 5000,
        ),
      );

      final export = await exportService.buildPayeeLedgerExport(
        format: format,
        entries: page.entries,
        metadata: StatementExportMetadata(
          statementTitle: l10n.groupPaymentLedgerTitle,
          fileStem: l10n.groupPaymentLedgerFileStem,
          userName: authState.user?.fullName ?? l10n.groupStatementsCoolUser,
          officialPhone:
              authState.user?.officialPhone ?? authState.user?.phone ?? '',
          generatedAt: DateTime.now(),
          periodLabel: periodLabel,
          filterLabel: groupName,
          sortLabel: l10n.newestFirst,
        ),
      );

      await downloadService.saveExport(export);
      if (mounted) {
        CoolToast.success(context, l10n.groupStatementsLedgerExported);
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
      return context.l10n.groupStatementsAllPostedEntriesInView;
    }
    final startLabel = start == null ? '...' : formatExportDateLabel(start);
    final endLabel = end == null ? '...' : formatExportDateLabel(end);
    return '$startLabel - $endLabel';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final accessAsync = ref.watch(groupAccessProvider(widget.groupId));
    final ledgerAsync = ref.watch(
      groupTransactionFeedProvider(
        GroupPaymentLedgerQuery(
          groupId: widget.groupId,
          statementQuery: _query,
        ),
      ),
    );

    final access = accessAsync.valueOrNull;
    final canViewTransactions = access?.canViewTransactions ?? false;
    final canExportLedger = access?.canExportLedger ?? false;
    final groupName =
        groupAsync.valueOrNull?.name ??
        context.l10n.groupStatementsGroupLedgerUpper;

    return CoreDetailScaffold(
      title: Text(
        context.l10n.groupStatementsTitleUpper,
        style: context.coolText.displayCondensed(
          Theme.of(context).textTheme.headlineSmall,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        groupAsync.when(
          data: (g) =>
              g?.name.toUpperCase() ??
              context.l10n.groupStatementsGroupLedgerUpper,
          loading: () => context.l10n.groupStatementsLoadingUpper,
          error: (_, _) => context.l10n.groupStatementsGroupLedgerUpper,
        ),
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
        if (canExportLedger)
          IconButton(
            onPressed: _isExportingPdf
                ? null
                : () => _export(
                    format: StatementExportFormat.pdf,
                    groupName: groupName,
                  ),
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(CoolIcons.pdf, color: colors.primaryText),
          ),
        if (canExportLedger)
          IconButton(
            onPressed: _isExportingExcel
                ? null
                : () => _export(
                    format: StatementExportFormat.excel,
                    groupName: groupName,
                  ),
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
      child: accessAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
          children: [_LockedState(colors)],
        ),
        data: (snapshot) {
          if (snapshot == null || !canViewTransactions) {
            return ListView(
              padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
              children: [_LockedState(colors)],
            );
          }

          return ledgerAsync.when(
            data: (page) {
              if (page.entries.isEmpty) {
                return ListView(
                  padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
                  children: [_EmptyState(colors)],
                );
              }

              final canLoadMore = page.entries.length < page.totalCount;
              return ListView.builder(
                padding: EdgeInsets.only(bottom: CoolSpace.x8 + bottomPad),
                itemCount: page.entries.length + (canLoadMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == page.entries.length) {
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
                  final isAdmin =
                      accessAsync.valueOrNull?.isPrivilegedAdmin ?? false;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: CoolSpace.x3),
                    child: _StatementTile(
                      entry: page.entries[index],
                      canManageAllocations: isAdmin,
                      groupId: widget.groupId,
                    ),
                  );
                },
              );
            },
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
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.colors);

  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      borderRadius: CoolRadii.xl,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.cardSurfaceStrong,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
               Icons.receipt_long_rounded,
              color: colors.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            context.l10n.groupStatementsNoTransactionsYetUpper,
            style: context.coolText.displayCondensed(
              Theme.of(context).textTheme.titleLarge,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            context.l10n.groupStatementsEmptyMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedState extends StatelessWidget {
  const _LockedState(this.colors);

  final CoolSemanticColors colors;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.xl,
      child: Center(
        child: Icon(
          CoolIcons.lock,
          color: colors.tertiaryText,
          size: 28,
        ),
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
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderRadius: CoolRadii.xl,
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.secondaryText),
      ),
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({
    required this.entry,
    this.canManageAllocations = false,
    this.groupId = '',
  });

  final PayeePaymentLedgerEntry entry;
  final bool canManageAllocations;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final isAllocated = entry.payerUserId.trim().isNotEmpty;
    final statusLabel = isAllocated ? 'confirmed' : 'pending_review';

    return CoolCard(
      borderRadius: CoolRadii.xl,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: colors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: CoolSpace.x4),
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
                      '${entry.payerName} • ${formatTransactionDate(entry.occurredAt)}',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                    style: context.coolText.mono(
                      Theme.of(context).textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
                      color: colors.accentGold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TransactionStatusChip(status: statusLabel),
                ],
              ),
              if (canManageAllocations) ...[
                const SizedBox(width: CoolSpace.x2),
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    onPressed: () => TransactionAllocationSheet.show(
                      context,
                      entry: entry,
                      groupId: groupId,
                    ),
                    icon: Icon(CoolIcons.settings, color: colors.secondaryText),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
