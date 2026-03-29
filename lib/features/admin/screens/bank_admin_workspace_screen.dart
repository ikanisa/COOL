import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/providers/auth_provider.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../../momo/services/momo_statement_export_service.dart';
import '../../partners/providers/partner_provider.dart';
import '../models/bank_admin_models.dart';
import '../providers/bank_admin_providers.dart';

enum _BankWorkspaceTab { overview, allocations, ledgers }

class BankAdminWorkspaceScreen extends ConsumerStatefulWidget {
  const BankAdminWorkspaceScreen({required this.partnerId, super.key});

  final String partnerId;

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
    final workspaceAsync = ref.watch(
      bankAdminWorkspaceProvider(widget.partnerId),
    );
    final partnerAsync = ref.watch(partnerByIdProvider(widget.partnerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          partnerAsync.maybeWhen(
            data: (partner) => '${partner?.name ?? 'Bank'} Terminal',
            orElse: () => 'Bank Terminal',
          ),
        ),
      ),
      body: workspaceAsync.when(
        data: (snapshot) {
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

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${snapshot.allocations.totalCount} pending allocation'
                  '${snapshot.allocations.totalCount == 1 ? '' : 's'}',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    _TabButton(
                      label: 'OVERVIEW',
                      isActive: _activeTab == _BankWorkspaceTab.overview,
                      onTap: () {
                        setState(() => _activeTab = _BankWorkspaceTab.overview);
                      },
                    ),
                    _TabButton(
                      label: 'ALLOCATIONS',
                      isActive: _activeTab == _BankWorkspaceTab.allocations,
                      onTap: () {
                        setState(
                          () => _activeTab = _BankWorkspaceTab.allocations,
                        );
                      },
                    ),
                    _TabButton(
                      label: 'LEDGERS',
                      isActive: _activeTab == _BankWorkspaceTab.ledgers,
                      onTap: () {
                        setState(() => _activeTab = _BankWorkspaceTab.ledgers);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: switch (_activeTab) {
                    _BankWorkspaceTab.overview => _OverviewTab(
                      snapshot: snapshot,
                      onViewDetails: (groupId) {
                        setState(() {
                          _selectedGroupId = groupId;
                        });
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
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
      ),
    );
  }

  Future<void> _allocateReview(
    BankAdminAllocationReviewItem item,
    BankAdminWorkspaceSnapshot snapshot,
  ) async {
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Allocate payment'),
          content: const Text('Assign this payment to the matched member.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final repository = ref.read(bankAdminRepositoryProvider);
                await repository.allocateManualReviewToGroupContribution(
                  partnerId: widget.partnerId,
                  reviewId: item.reviewId,
                  groupId: item.groupId,
                  memberUserId: member.userId,
                );
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Allocate to member'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _rejectReview(BankAdminAllocationReviewItem item) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reject allocation'),
          content: const Text('This removes the pending allocation.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final repository = ref.read(bankAdminRepositoryProvider);
                await repository.rejectManualReviewAllocation(
                  partnerId: widget.partnerId,
                  reviewId: item.reviewId,
                );
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportLedger(
    String groupId,
    AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync,
  ) async {
    final page = ledgerAsync.valueOrNull;
    if (groupId.isEmpty || page == null) {
      return;
    }

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
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(fontWeight: isActive ? FontWeight.w700 : null),
      ),
    );
  }
}

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
    final group = snapshot.groups.entries.firstOrNull;
    if (group == null) {
      return const Center(child: Text('No linked groups.'));
    }

    final members = snapshot.members.entries
        .where((entry) => entry.groupId == group.id)
        .toList(growable: false);

    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.group.name),
                const SizedBox(height: 8),
                Text('${snapshot.allocations.totalCount} manual review'),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => onViewDetails(group.id),
                  child: const Text('View details'),
                ),
                const SizedBox(height: 12),
                Text('Linked group profile: ${group.group.name}'),
                const SizedBox(height: 8),
                for (final member in members) Text(member.displayName),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => onOpenLedger(group.id),
                  child: const Text('Open ledger'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

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
    if (snapshot.allocations.entries.isEmpty) {
      return const Center(child: Text('No manual review items.'));
    }

    final item = snapshot.allocations.entries.first;
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Manual Review'),
                const SizedBox(height: 8),
                Text(item.groupName),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => onAllocate(item),
                      child: const Text('Allocate'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => onReject(item),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LedgersTab extends StatelessWidget {
  const _LedgersTab({required this.ledgerAsync, required this.onExportExcel});

  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final Future<void> Function() onExportExcel;

  @override
  Widget build(BuildContext context) {
    return ledgerAsync.when(
      data: (page) => ListView(
        children: [
          const Text('Posted payment ledger'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: onExportExcel,
              tooltip: 'Export Excel',
              icon: const Icon(
                Icons.file_download_outlined,
                semanticLabel: 'Export Excel',
              ),
            ),
          ),
          for (final entry in page.entries)
            ListTile(
              title: Text(entry.label),
              subtitle: Text(entry.payerName),
              trailing: Text(
                '${_BankAdminWorkspaceScreenState._amountFormat.format(entry.amount)} RWF',
              ),
            ),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load: $error')),
    );
  }
}
