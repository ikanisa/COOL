import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/core_detail_scaffold.dart';
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
          statementTitle: 'Group Payment Ledger',
          fileStem: 'cool_group_payment_ledger',
          userName: authState.user?.fullName ?? 'COOL User',
          officialPhone:
              authState.user?.officialPhone ?? authState.user?.phone ?? '',
          generatedAt: DateTime.now(),
          periodLabel: _periodLabel(),
          filterLabel: groupName,
          sortLabel: 'Newest first',
        ),
      );

      await downloadService.saveExport(export);
      if (mounted) {
        CoolToast.success(context, 'Ledger exported');
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
      return 'All posted entries in view';
    }
    final startLabel = start == null ? '...' : _exportDateLabel(start);
    final endLabel = end == null
        ? '...'
        : _exportDateLabel(end);
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
    final groupName = groupAsync.valueOrNull?.name ?? 'GROUP LEDGER';

    return CoreDetailScaffold(
      title: Text(
        'STATEMENTS',
        style: context.coolText.displayCondensed(
          Theme.of(context).textTheme.headlineSmall,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        groupAsync.when(
          data: (g) => g?.name.toUpperCase() ?? 'GROUP LEDGER',
          loading: () => 'LOADING',
          error: (_, _) => 'GROUP LEDGER',
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
            Icons.calendar_month_rounded,
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
                : Icon(
                    Icons.picture_as_pdf_rounded,
                    color: colors.primaryText,
                  ),
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
                : Icon(
                    Icons.grid_on_rounded,
                    color: colors.primaryText,
                  ),
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
                            Icons.expand_circle_down_rounded,
                            color: colors.accent,
                            size: 28,
                          ),
                        ),
                      ),
                    );
                  }
                  final isAdmin = accessAsync.valueOrNull?.isPrivilegedAdmin ?? false;
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
              Icons.receipt_long_rounded,
              color: colors.accent,
              size: 32,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            'NO TRANSACTIONS YET',
            style: context.coolText.displayCondensed(
              Theme.of(context).textTheme.titleLarge,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Contributions will appear here as members make payments to this group.',
            textAlign: TextAlign.center,
            style: context.coolText.mono(
              Theme.of(context).textTheme.bodySmall,
              fontWeight: FontWeight.w600,
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
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.lock_outline_rounded,
        color: colors.tertiaryText,
        size: 28,
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
          fontWeight: FontWeight.w600,
          color: colors.secondaryText,
        ),
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

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
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
                      '${entry.payerName} • ${_formatDate(entry.occurredAt)}',
                      style: context.coolText.mono(
                        Theme.of(context).textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
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
                    '${entry.amount} ${entry.currency}',
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
                    icon: Icon(
                      Icons.tune_rounded,
                      color: colors.secondaryText,
                    ),
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

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = switch (local.month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month ${local.year} • $hour:$minute';
}

String _exportDateLabel(DateTime value) {
  final local = value.toLocal();
  final month = switch (local.month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
  return '${local.day.toString().padLeft(2, '0')} $month ${local.year}';
}
