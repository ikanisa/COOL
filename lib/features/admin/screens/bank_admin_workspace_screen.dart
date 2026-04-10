import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cool_foundations.dart';
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
  static final NumberFormat _amountFormat = NumberFormat.decimalPattern(
    'en_US',
  );

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
                  onExportExcel: () =>
                      _exportLedger(resolvedGroupId, ledgerAsync),
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
                        style: TextStyle(color: colors.secondaryText),
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
                        style: TextStyle(color: colors.secondaryText),
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

  Future<void> _exportLedger(
    String groupId,
    AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync,
  ) async {
    final page = ledgerAsync.valueOrNull;
    if (groupId.isEmpty || page == null) return;

    final authState = ref.read(authProvider);
    final exportService = ref.read(momoStatementExportServiceProvider);
    final downloadService = ref.read(momoStatementDownloadServiceProvider);

    final export = await exportService.buildPayeeLedgerExport(
      format: StatementExportFormat.excel,
      entries: page.entries,
      metadata: StatementExportMetadata(
        statementTitle: 'Group Payment Ledger',
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

// ═══════════════════════════════════════════════════════════════
// Tab row
// ═══════════════════════════════════════════════════════════════

class _TabRow extends StatelessWidget {
  const _TabRow({required this.activeTab, required this.onTabChanged});

  final _BankWorkspaceTab activeTab;
  final ValueChanged<_BankWorkspaceTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in _BankWorkspaceTab.values) ...[
            ChoiceChip(
              showCheckmark: false,
              label: Text(tab.name.toUpperCase()),
              selected: activeTab == tab,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                onTabChanged(tab);
              },
              backgroundColor: colors.chipBackground,
              selectedColor: colors.chipSelectedBackground,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: activeTab == tab
                    ? colors.accentStrong
                    : colors.secondaryText,
              ),
              side: BorderSide.none,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(CoolRadii.pill)),
              ),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Overview tab
// ═══════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.snapshot,
    required this.onViewDetails,
    required this.onOpenLedger,
  });

  final BankAdminWorkspaceSnapshot snapshot;
  final void Function(String groupId) onViewDetails;
  final void Function(String groupId) onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final group = snapshot.groups.entries.firstOrNull;

    if (group == null) {
      return const CoolEmptyView(
        message: 'No linked groups.',
        icon: Icons.group_off_rounded,
      );
    }

    final members = snapshot.members.entries
        .where((entry) => entry.groupId == group.id)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoolCard(
          backgroundColor: colors.operationalSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.group.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                '${snapshot.allocations.totalCount} manual review',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Row(
                children: [
                  _ActionChip(
                    label: 'View details',
                    icon: Icons.visibility_outlined,
                    onTap: () => onViewDetails(group.id),
                  ),
                  const SizedBox(width: CoolSpace.x2),
                  _ActionChip(
                    label: 'Open ledger',
                    icon: Icons.receipt_long_outlined,
                    onTap: () => onOpenLedger(group.id),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (members.isNotEmpty) ...[
          const SizedBox(height: CoolSpace.x5),
          const AdminSectionHeader(title: 'Group Members'),
          const SizedBox(height: CoolSpace.x3),
          for (final member in members) ...[
            CoolCard(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.info.withValues(alpha: 0.12),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.xs),
                      ),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: colors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      member.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
          ],
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Allocations tab
// ═══════════════════════════════════════════════════════════════

class _AllocationsTab extends StatelessWidget {
  const _AllocationsTab({
    required this.snapshot,
    required this.onAllocate,
    required this.onReject,
  });

  final BankAdminWorkspaceSnapshot snapshot;
  final Future<void> Function(BankAdminAllocationReviewItem item) onAllocate;
  final Future<void> Function(BankAdminAllocationReviewItem item) onReject;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    if (snapshot.allocations.entries.isEmpty) {
      return const CoolEmptyView(
        message: 'No manual review items.',
        icon: Icons.check_circle_outline_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in snapshot.allocations.entries) ...[
          CoolCard(
            backgroundColor: colors.operationalSurface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.12),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(CoolRadii.xs),
                        ),
                      ),
                      child: Icon(
                        Icons.pending_actions_rounded,
                        size: 16,
                        color: colors.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.groupName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x4),
                Row(
                  children: [
                    _ActionChip(
                      label: 'Allocate',
                      icon: Icons.check_rounded,
                      onTap: () => onAllocate(item),
                    ),
                    const SizedBox(width: CoolSpace.x2),
                    _ActionChip(
                      label: 'Reject',
                      icon: Icons.close_rounded,
                      isDestructive: true,
                      onTap: () => onReject(item),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Ledgers tab
// ═══════════════════════════════════════════════════════════════

class _LedgersTab extends StatelessWidget {
  const _LedgersTab({required this.ledgerAsync, required this.onExportExcel});

  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final Future<void> Function() onExportExcel;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolAsyncView<MomoStatementPage<PayeePaymentLedgerEntry>>(
      value: ledgerAsync,
      onRetry: () {},
      loadingWidget: const CoolSkeletonList(itemCount: 4),
      emptyCheck: (page) => page.entries.isEmpty,
      emptyWidget: const CoolEmptyView(
        message: 'No posted payment ledger entries.',
        icon: Icons.receipt_long_outlined,
      ),
      builder: (page) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Posted payment ledger',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                IconButton(
                  onPressed: onExportExcel,
                  tooltip: 'Export Excel',
                  icon: Icon(
                    Icons.file_download_outlined,
                    color: colors.primaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CoolSpace.x3),
            for (final entry in page.entries) ...[
              CoolCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.payerName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.tertiaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_BankAdminWorkspaceScreenState._amountFormat.format(entry.amount)} RWF',
                      style: context.coolText.mono(
                        theme.textTheme.titleSmall,
                        fontWeight: FontWeight.w800,
                        color: colors.success,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
            ],
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Action chip (shared)
// ═══════════════════════════════════════════════════════════════

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final color = isDestructive ? colors.danger : colors.accent;

    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(CoolRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
