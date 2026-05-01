import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/admin_section_header.dart';

import '../../auth/providers/auth_provider.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../../momo/services/momo_statement_export_service.dart';

import '../models/bank_admin_models.dart';
import '../providers/bank_admin_providers.dart';

part 'bank_admin_workspace_parts.dart';

enum _BankWorkspaceTab { overview, allocations, ledgers }

class BankAdminWorkspaceScreen extends ConsumerStatefulWidget {
  const BankAdminWorkspaceScreen({required this.bankId, super.key});

  final String bankId;

  @override
  ConsumerState<BankAdminWorkspaceScreen> createState() =>
      _BankAdminWorkspaceScreenState();
}

class _BankAdminWorkspaceScreenState
    extends ConsumerState<BankAdminWorkspaceScreen> {
  _BankWorkspaceTab _activeTab = _BankWorkspaceTab.overview;
  String? _selectedGroupId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspaceAsync = ref.watch(bankAdminWorkspaceProvider(widget.bankId));

    return AdminDetailScaffold(
      title: Text(
        'Bank Terminal',
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      child: CoolAsyncView<BankAdminWorkspaceSnapshot>(
        value: workspaceAsync,
        onRetry: () =>
            ref.invalidate(bankAdminWorkspaceProvider(widget.bankId)),
        loadingWidget: const Padding(
          padding: EdgeInsets.only(bottom: CoolSpace.x7),
          child: CoolSkeletonList(itemCount: 5),
        ),
        emptyCheck: (_) => false,
        builder: (snapshot) {
          final colors = context.coolSemanticColors;
          final selectedGroup = snapshot.groups.entries
              .where((group) => group.id == _selectedGroupId)
              .cast<BankAdminGroupSummary?>()
              .firstWhere(
                (group) => group != null,
                orElse: () => snapshot.groups.entries.isEmpty
                    ? null
                    : snapshot.groups.entries.first,
              );
          final resolvedGroupId = selectedGroup?.id ?? '';
          final ledgerAsync = resolvedGroupId.isEmpty
              ? const AsyncData(MomoStatementPage<PayeePaymentLedgerEntry>())
              : ref.watch(
                  groupPaymentLedgerProvider(
                    GroupPaymentLedgerQuery(groupId: resolvedGroupId),
                  ),
                );

          return ListView(
            padding: const EdgeInsets.only(bottom: CoolSpace.x7),
            children: [
              Text(
                '${snapshot.allocations.totalCount} pending allocation'
                '${snapshot.allocations.totalCount == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              _TabRow(
                activeTab: _activeTab,
                onTabChanged: (tab) => setState(() => _activeTab = tab),
              ),
              const SizedBox(height: CoolSpace.x5),
              switch (_activeTab) {
                _BankWorkspaceTab.overview => _OverviewTab(
                  snapshot: snapshot,
                  onViewDetails: (groupId) {
                    setState(() => _selectedGroupId = groupId);
                  },
                  onOpenLedger: (groupId) {
                    setState(() {
                      _selectedGroupId = groupId;
                      _activeTab = _BankWorkspaceTab.ledgers;
                    });
                  },
                ),
                _BankWorkspaceTab.allocations => _AllocationsTab(
                  snapshot: snapshot,
                  onAllocate: (item) => _allocateReview(item, snapshot),
                  onReject: _rejectReview,
                ),
                _BankWorkspaceTab.ledgers => _LedgersTab(
                  ledgerAsync: ledgerAsync,
                  onExportPdf: () => _exportLedger(
                    groupId: resolvedGroupId,
                    groupName:
                        selectedGroup?.group.name ?? 'Group Payment Ledger',
                    format: StatementExportFormat.pdf,
                  ),
                  onExportExcel: () => _exportLedger(
                    groupId: resolvedGroupId,
                    groupName:
                        selectedGroup?.group.name ?? 'Group Payment Ledger',
                    format: StatementExportFormat.excel,
                  ),
                ),
              },
            ],
          );
        },
      ),
    );
  }

  Future<void> _allocateReview(
    BankAdminAllocationReviewItem item,
    BankAdminWorkspaceSnapshot snapshot,
  ) async {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final member = snapshot.members.entries.firstWhere(
      (entry) => entry.groupId == item.groupId,
      orElse: () => const BankAdminMemberRecord(
        groupId: '',
        groupName: '',
        userId: '',
        displayName: '',
        contributionAmount: 0,
      ),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: colors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CoolRadii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(CoolSpace.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allocate payment',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x3),
                Text(
                  'Assign this payment to the matched member.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: CoolSpace.x5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        'Cancel',
                        style: context.coolText.mobiLabel(
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: CoolSpace.x2),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                        ),
                      ),
                      onPressed: () async {
                        final repository = ref.read(
                          bankAdminRepositoryProvider,
                        );
                        await repository
                            .allocateManualReviewToGroupContribution(
                              bankId: widget.bankId,
                              reviewId: item.reviewId,
                              groupId: item.groupId,
                              memberUserId: member.userId,
                            );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (!mounted) return;
                        CoolToast.success(context, 'Payment allocated');
                      },
                      child: const Text('Allocate'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _rejectReview(BankAdminAllocationReviewItem item) async {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: colors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CoolRadii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.all(CoolSpace.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reject allocation',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x3),
                Text(
                  'This removes the pending allocation.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: CoolSpace.x5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(
                        'Cancel',
                        style: context.coolText.mobiLabel(
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: CoolSpace.x2),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.danger,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                        ),
                      ),
                      onPressed: () async {
                        final repository = ref.read(
                          bankAdminRepositoryProvider,
                        );
                        await repository.rejectManualReviewAllocation(
                          bankId: widget.bankId,
                          reviewId: item.reviewId,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (!mounted) return;
                        CoolToast.success(context, 'Allocation rejected');
                      },
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportLedger({
    required String groupId,
    required String groupName,
    required StatementExportFormat format,
  }) async {
    if (groupId.isEmpty) return;

    final repository = ref.read(momoStatementRepositoryProvider);
    final authState = ref.read(authProvider);
    final exportService = ref.read(momoStatementExportServiceProvider);
    final downloadService = ref.read(momoStatementDownloadServiceProvider);
    final page = await repository.loadGroupPaymentLedgerEntriesPage(
      groupId,
      query: const MomoStatementQuery(limit: 5000),
    );

    final export = await exportService.buildPayeeLedgerExport(
      format: format,
      entries: page.entries,
      metadata: StatementExportMetadata(
        statementTitle: groupName,
        fileStem: 'cool_group_payment_ledger',
        userName: authState.user?.fullName ?? 'COOL User',
        officialPhone:
            authState.user?.officialPhone ?? authState.user?.phone ?? '',
        generatedAt: DateTime.now(),
        periodLabel: 'All posted entries in view',
        filterLabel: 'Group payment ledger',
        sortLabel: 'Newest first',
      ),
    );

    await downloadService.saveExport(export);
    if (mounted) {
      CoolToast.success(context, 'Ledger exported');
    }
  }
}
