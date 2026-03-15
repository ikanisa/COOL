import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../../momo/services/momo_statement_export_service.dart';
import '../../partners/providers/partner_provider.dart';
import '../models/bank_admin_models.dart';
import '../providers/bank_admin_providers.dart';
import '../widgets/admin_workspace_gate.dart';

class BankAdminWorkspaceScreen extends ConsumerStatefulWidget {
  const BankAdminWorkspaceScreen({required this.partnerId, super.key});

  final String partnerId;

  @override
  ConsumerState<BankAdminWorkspaceScreen> createState() =>
      _BankAdminWorkspaceScreenState();
}

class _BankAdminWorkspaceScreenState
    extends ConsumerState<BankAdminWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _selectedGroupId;
  bool _isExportingLedger = false;
  String? _activeReviewId;
  String? _activeReviewAction;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _syncSelectedGroup(List<BankAdminGroupSummary> groups) {
    final hasSelection =
        _selectedGroupId != null &&
        groups.any((group) => group.id == _selectedGroupId);
    final nextSelection = groups.isEmpty ? null : groups.first.id;

    if (hasSelection || nextSelection == _selectedGroupId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _selectedGroupId = nextSelection);
    });
  }

  BankAdminGroupSummary? _selectedGroup(List<BankAdminGroupSummary> groups) {
    for (final group in groups) {
      if (group.id == _selectedGroupId) {
        return group;
      }
    }
    return groups.isEmpty ? null : groups.first;
  }

  void _openLedgerTab(String groupId) {
    setState(() => _selectedGroupId = groupId);
    _tabController.animateTo(3);
  }

  void _openGroupDetail(
    BankAdminGroupSummary group,
    BankAdminWorkspaceSnapshot snapshot,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _GroupDetailSheet(
        group: group,
        members: snapshot.members.entries
            .where((member) => member.groupId == group.id)
            .toList(growable: false),
        contributions: snapshot.contributions.entries
            .where((contribution) => contribution.groupId == group.id)
            .toList(growable: false),
        onOpenLedger: group.id.isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                _openLedgerTab(group.id);
              },
      ),
    );
  }

  Future<void> _exportLedger({
    required String partnerName,
    required BankAdminGroupSummary group,
    required List<PayeePaymentLedgerEntry> entries,
  }) async {
    if (_isExportingLedger || entries.isEmpty) {
      return;
    }

    setState(() => _isExportingLedger = true);
    try {
      final authState = ref.read(authProvider);
      final exportService = ref.read(momoStatementExportServiceProvider);
      final downloadService = ref.read(momoStatementDownloadServiceProvider);
      final export = await exportService.buildPayeeLedgerExport(
        format: StatementExportFormat.excel,
        entries: entries,
        metadata: StatementExportMetadata(
          statementTitle: '${group.group.name} payment ledger',
          fileStem:
              'bank_${_fileSafe(partnerName)}_${_fileSafe(group.group.name)}_ledger',
          userName: authState.user?.fullName.trim().isNotEmpty == true
              ? authState.user!.fullName.trim()
              : partnerName,
          officialPhone:
              authState.user?.officialPhone ??
              authState.user?.phone ??
              group.group.bankPartner ??
              '',
          generatedAt: DateTime.now(),
          periodLabel: 'All posted entries in view',
          filterLabel: 'Group payment ledger',
          sortLabel: 'Newest first',
        ),
      );
      final result = await downloadService.saveExport(export);
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'Ledger exported to ${result.fileName}.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Could not export this ledger right now.');
    } finally {
      if (mounted) {
        setState(() => _isExportingLedger = false);
      }
    }
  }

  Future<void> _allocateManualReview({
    required BankAdminAllocationReviewItem item,
    required String groupId,
    required String memberUserId,
  }) async {
    if (_activeReviewId != null) {
      return;
    }

    setState(() {
      _activeReviewId = item.reviewId;
      _activeReviewAction = 'allocate';
    });

    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.allocateManualReviewToGroupContribution(
        partnerId: widget.partnerId,
        reviewId: item.reviewId,
        groupId: groupId,
        memberUserId: memberUserId,
      );
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      ref.invalidate(
        groupPaymentLedgerProvider(
          GroupPaymentLedgerQuery(
            groupId: groupId,
            statementQuery: const MomoStatementQuery(limit: 100),
          ),
        ),
      );
      if (mounted) {
        setState(() => _selectedGroupId = groupId);
        CoolToast.success(
          context,
          'Payment allocated to the selected group member.',
        );
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not allocate this payment right now.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeReviewId = null;
          _activeReviewAction = null;
        });
      }
    }
  }

  Future<void> _rejectManualReview(BankAdminAllocationReviewItem item) async {
    if (_activeReviewId != null) {
      return;
    }

    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject allocation'),
        content: Text(
          'This will remove the payment from the manual review queue for ${item.groupName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (shouldReject != true || !mounted) {
      return;
    }

    setState(() {
      _activeReviewId = item.reviewId;
      _activeReviewAction = 'reject';
    });

    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.rejectManualReviewAllocation(
        partnerId: widget.partnerId,
        reviewId: item.reviewId,
      );
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      if (mounted) {
        CoolToast.success(context, 'Payment marked as rejected.');
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not reject this payment right now.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeReviewId = null;
          _activeReviewAction = null;
        });
      }
    }
  }

  Future<void> _showAllocationSheet(
    BankAdminAllocationReviewItem item,
    BankAdminWorkspaceSnapshot snapshot,
  ) async {
    if (_activeReviewId != null || snapshot.groups.entries.isEmpty) {
      return;
    }

    final groups = snapshot.groups.entries;
    String selectedGroupId =
        groups.any((group) => group.id == item.groupId && group.id.isNotEmpty)
        ? item.groupId
        : groups.first.id;

    List<BankAdminMemberRecord> membersFor(String groupId) {
      return snapshot.members.entries
          .where((member) => member.groupId == groupId)
          .toList(growable: false);
    }

    String? initialMemberId() {
      final scopedMembers = membersFor(selectedGroupId);
      if (scopedMembers.isEmpty) {
        return null;
      }

      final matchedMember = scopedMembers.where(
        (member) => member.userId == item.payerUserId,
      );
      if (matchedMember.isNotEmpty) {
        return matchedMember.first.userId;
      }
      return scopedMembers.first.userId;
    }

    String? selectedMemberId = initialMemberId();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final scopedMembers = membersFor(selectedGroupId);
          if (selectedMemberId != null &&
              scopedMembers.every(
                (member) => member.userId != selectedMemberId,
              )) {
            selectedMemberId = scopedMembers.isEmpty
                ? null
                : scopedMembers.first.userId;
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Allocate payment',
                    style: GoogleFonts.dmSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${NumberFormat.decimalPattern('en_US').format(item.amount)} RWF · ${item.groupName}',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedGroupId,
                    decoration: const InputDecoration(labelText: 'Group'),
                    items: groups
                        .map(
                          (group) => DropdownMenuItem<String>(
                            value: group.id,
                            child: Text(group.group.name),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setModalState(() {
                        selectedGroupId = value;
                        final nextMembers = membersFor(value);
                        selectedMemberId = nextMembers.isEmpty
                            ? null
                            : nextMembers.first.userId;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMemberId,
                    decoration: const InputDecoration(labelText: 'Member'),
                    items: scopedMembers
                        .map(
                          (member) => DropdownMenuItem<String>(
                            value: member.userId,
                            child: Text(member.displayName),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: scopedMembers.isEmpty
                        ? null
                        : (value) =>
                              setModalState(() => selectedMemberId = value),
                  ),
                  if (scopedMembers.isEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'No visible members are linked to the selected group.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selectedMemberId == null
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await _allocateManualReview(
                                item: item,
                                groupId: selectedGroupId,
                                memberUserId: selectedMemberId!,
                              );
                            },
                      child: const Text('Allocate to member'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return BankAdminGate(
      partnerId: widget.partnerId,
      child: ref
          .watch(partnerByIdProvider(widget.partnerId))
          .when(
            data: (partner) {
              final partnerName = partner?.name ?? 'Bank';
              final workspaceAsync = ref.watch(
                bankAdminWorkspaceProvider(widget.partnerId),
              );

              return Scaffold(
                backgroundColor: palette.bg,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  iconTheme: IconThemeData(color: palette.text),
                ),
                body: CoolAsyncView<BankAdminWorkspaceSnapshot>(
                  value: workspaceAsync,
                  onRetry: () => ref.invalidate(
                    bankAdminWorkspaceProvider(widget.partnerId),
                  ),
                  builder: (snapshot) {
                    _syncSelectedGroup(snapshot.groups.entries);
                    final selectedGroup = _selectedGroup(
                      snapshot.groups.entries,
                    );
                    final ledgerQuery = selectedGroup == null
                        ? null
                        : GroupPaymentLedgerQuery(
                            groupId: selectedGroup.id,
                            statementQuery: const MomoStatementQuery(
                              limit: 100,
                            ),
                          );
                    final ledgerAsync = ledgerQuery == null
                        ? const AsyncValue.data(
                            MomoStatementPage<PayeePaymentLedgerEntry>(),
                          )
                        : ref.watch(groupPaymentLedgerProvider(ledgerQuery));

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                      children: [
                        Text(
                          '$partnerName Admin',
                          style: GoogleFonts.dmSans(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: palette.text,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _WorkspaceHero(
                          partnerName: partnerName,
                          snapshot: snapshot,
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: palette.border),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            labelColor: palette.text,
                            unselectedLabelColor: palette.text3,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: palette.surface2,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            labelStyle: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            unselectedLabelStyle: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            tabs: const [
                              Tab(text: 'Groups'),
                              Tab(text: 'Members'),
                              Tab(text: 'Contributions'),
                              Tab(text: 'Ledgers'),
                              Tab(text: 'Allocations'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 600, // Fixed height for TabBarView inside ListView
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _GroupsTab(
                                groups: snapshot.groups.entries,
                                totalCount: snapshot.groups.totalCount,
                                onOpenGroup: (group) =>
                                    _openGroupDetail(group, snapshot),
                                onOpenLedger: _openLedgerTab,
                              ),
                              _MembersTab(
                                members: snapshot.members.entries,
                                totalCount: snapshot.members.totalCount,
                              ),
                              _ContributionsTab(
                                contributions: snapshot.contributions.entries,
                                totalCount: snapshot.contributions.totalCount,
                              ),
                              _LedgersTab(
                                groups: snapshot.groups.entries,
                                selectedGroupId: _selectedGroupId,
                                onSelectedGroupChanged: (value) {
                                  setState(() => _selectedGroupId = value);
                                },
                                ledgerAsync: ledgerAsync,
                                onRetry: ledgerQuery == null
                                    ? null
                                    : () => ref.invalidate(
                                        groupPaymentLedgerProvider(
                                          ledgerQuery,
                                        ),
                                      ),
                                onExportExcel: selectedGroup == null
                                    ? null
                                    : (entries) => _exportLedger(
                                        partnerName: partnerName,
                                        group: selectedGroup,
                                        entries: entries,
                                      ),
                                isExporting: _isExportingLedger,
                              ),
                              _AllocationsTab(
                                items: snapshot.allocations.entries,
                                totalCount: snapshot.allocations.totalCount,
                                activeReviewId: _activeReviewId,
                                activeAction: _activeReviewAction,
                                onAllocate: (item) =>
                                    _showAllocationSheet(item, snapshot),
                                onReject: _rejectManualReview,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
            loading: () => const AdminLoadingScaffold(title: 'Bank Admin'),
            error: (_, _) => const AdminAccessDeniedScaffold(
              title: 'Bank Admin',
              message: 'The bank workspace could not be loaded.',
            ),
          ),
    );
  }
}

class _WorkspaceHero extends StatelessWidget {
  const _WorkspaceHero({required this.partnerName, required this.snapshot});

  final String partnerName;
  final BankAdminWorkspaceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      backgroundColor: AppColors.surface,
      borderColor: AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            partnerName,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Custodian workspace for group savings oversight, contribution review, payment ledgers, and manual allocation follow-up.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricChip(
                label: 'groups',
                value: snapshot.groups.totalCount.toString(),
              ),
              _MetricChip(
                label: 'members',
                value: snapshot.members.totalCount.toString(),
              ),
              _MetricChip(
                label: 'contributions',
                value: snapshot.contributions.totalCount.toString(),
              ),
              _MetricChip(
                label: 'manual review',
                value: snapshot.allocations.totalCount.toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$value $label',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
    );
  }
}

class _GroupsTab extends StatelessWidget {
  const _GroupsTab({
    required this.groups,
    required this.totalCount,
    required this.onOpenGroup,
    required this.onOpenLedger,
  });

  final List<BankAdminGroupSummary> groups;
  final int totalCount;
  final ValueChanged<BankAdminGroupSummary> onOpenGroup;
  final ValueChanged<String> onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy');

    if (groups.isEmpty) {
      return const CoolEmptyView(
        message: 'No custodial groups are linked to this bank yet.',
        compact: true,
      );
    }

    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = groups[index];
        return CoolCard(
          backgroundColor: AppColors.surface,
          borderColor: AppColors.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.group.name,
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_title(item.group.type)} · ${_title(item.group.visibility)}',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((item.group.description?.trim().isNotEmpty ?? false)) ...[
                const SizedBox(height: 8),
                Text(
                  item.group.description!.trim(),
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoPill(
                    label: 'Balance',
                    value: '${moneyFormat.format(item.group.amount)} RWF',
                  ),
                  _InfoPill(
                    label: 'Members',
                    value: item.group.memberCount.toString(),
                  ),
                  _InfoPill(label: 'Admins', value: item.adminCount.toString()),
                  _InfoPill(
                    label: 'Contributions',
                    value: item.contributionCount.toString(),
                  ),
                  _InfoPill(
                    label: 'Monthly',
                    value: item.group.monthlyContribution == null
                        ? '-'
                        : '${moneyFormat.format(item.group.monthlyContribution)} RWF',
                  ),
                  _InfoPill(
                    label: 'Last activity',
                    value: item.lastContributionAt == null
                        ? '-'
                        : dateFormat.format(item.lastContributionAt!),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => onOpenGroup(item),
                    child: const Text('View details'),
                  ),
                  TextButton(
                    onPressed: item.id.isEmpty
                        ? null
                        : () => onOpenLedger(item.id),
                    child: const Text('View ledger'),
                  ),
                ],
              ),
              if (index == 0 && totalCount > groups.length) ...[
                const SizedBox(height: 12),
                Text(
                  'Showing ${groups.length} of $totalCount linked groups.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _GroupDetailSheet extends StatelessWidget {
  const _GroupDetailSheet({
    required this.group,
    required this.members,
    required this.contributions,
    this.onOpenLedger,
  });

  final BankAdminGroupSummary group;
  final List<BankAdminMemberRecord> members;
  final List<BankAdminContributionRecord> contributions;
  final VoidCallback? onOpenLedger;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                group.group.name,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Linked group profile, active members, and recent custodial contributions.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoPill(
                    label: 'Balance',
                    value: '${moneyFormat.format(group.group.amount)} RWF',
                  ),
                  _InfoPill(label: 'Members', value: members.length.toString()),
                  _InfoPill(
                    label: 'Contributions',
                    value: contributions.length.toString(),
                  ),
                  _InfoPill(
                    label: 'Raised',
                    value: '${moneyFormat.format(group.contributionTotal)} RWF',
                  ),
                ],
              ),
              if (onOpenLedger != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: onOpenLedger,
                    child: const Text('Open ledger'),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Members',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              if (members.isEmpty)
                const CoolEmptyView(
                  message: 'No member records are visible for this group yet.',
                  compact: true,
                )
              else
                ...members.map(
                  (member) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.displayName,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${moneyFormat.format(member.contributionAmount)} RWF contributed',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (member.isAdmin)
                            _StatusTag(
                              label: 'Admin',
                              backgroundColor: AppColors.rsBlueGlow,
                              foregroundColor: AppColors.rsWhite,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                'Recent contributions',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 10),
              if (contributions.isEmpty)
                const CoolEmptyView(
                  message:
                      'No contribution records are visible for this group yet.',
                  compact: true,
                )
              else
                ...contributions.map(
                  (contribution) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  contribution.contributorName,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              _StatusTag(
                                label: _title(contribution.status),
                                backgroundColor:
                                    contribution.status == 'confirmed'
                                    ? AppColors.accent.withValues(alpha: 0.12)
                                    : AppColors.orange.withValues(alpha: 0.12),
                                foregroundColor:
                                    contribution.status == 'confirmed'
                                    ? AppColors.accent
                                    : AppColors.orange,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${moneyFormat.format(contribution.amount)} RWF',
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateFormat.format(contribution.createdAt),
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text2,
                            ),
                          ),
                          if ((contribution.reference?.trim().isNotEmpty ??
                              false)) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Reference: ${contribution.reference}',
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.members, required this.totalCount});

  final List<BankAdminMemberRecord> members;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy');

    if (members.isEmpty) {
      return const CoolEmptyView(
        message: 'No members are visible for this bank workspace yet.',
        compact: true,
      );
    }

    return ListView.separated(
      itemCount: members.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final member = members[index];
        return CoolCard(
          backgroundColor: AppColors.surface,
          borderColor: AppColors.border,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.displayName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.groupName,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Contribution total: ${moneyFormat.format(member.contributionAmount)} RWF',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                    Text(
                      member.joinedAt == null
                          ? 'Joined: -'
                          : 'Joined: ${dateFormat.format(member.joinedAt!)}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              if (member.isAdmin)
                _StatusTag(
                  label: 'Admin',
                  backgroundColor: AppColors.rsBlueGlow,
                  foregroundColor: AppColors.rsWhite,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ContributionsTab extends StatelessWidget {
  const _ContributionsTab({
    required this.contributions,
    required this.totalCount,
  });

  final List<BankAdminContributionRecord> contributions;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    if (contributions.isEmpty) {
      return const CoolEmptyView(
        message: 'No custodial contributions are visible yet.',
        compact: true,
      );
    }

    return ListView.separated(
      itemCount: contributions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final contribution = contributions[index];
        return CoolCard(
          backgroundColor: AppColors.surface,
          borderColor: AppColors.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      contribution.contributorName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  _StatusTag(
                    label: _title(contribution.status),
                    backgroundColor: contribution.status == 'confirmed'
                        ? AppColors.accent.withValues(alpha: 0.12)
                        : AppColors.orange.withValues(alpha: 0.12),
                    foregroundColor: contribution.status == 'confirmed'
                        ? AppColors.accent
                        : AppColors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                contribution.groupName,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${moneyFormat.format(contribution.amount)} RWF',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateFormat.format(contribution.createdAt),
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              if ((contribution.reference?.trim().isNotEmpty ?? false)) ...[
                const SizedBox(height: 4),
                Text(
                  'Reference: ${contribution.reference}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LedgersTab extends StatelessWidget {
  const _LedgersTab({
    required this.groups,
    required this.selectedGroupId,
    required this.onSelectedGroupChanged,
    required this.ledgerAsync,
    required this.onRetry,
    required this.onExportExcel,
    required this.isExporting,
  });

  final List<BankAdminGroupSummary> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onSelectedGroupChanged;
  final AsyncValue<MomoStatementPage<PayeePaymentLedgerEntry>> ledgerAsync;
  final VoidCallback? onRetry;
  final Future<void> Function(List<PayeePaymentLedgerEntry> entries)?
  onExportExcel;
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const CoolEmptyView(
        message: 'Link at least one custodial group to browse ledgers.',
        compact: true,
      );
    }

    final selected = selectedGroupId;
    final selectedExists = groups.any((group) => group.id == selected);
    final resolvedValue = selectedExists ? selected : groups.first.id;

    return Column(
      children: [
        CoolCard(
          backgroundColor: AppColors.surface,
          borderColor: AppColors.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Posted payment ledger',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a group to inspect its posted payment ledger and export the current ledger view to Excel.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: resolvedValue,
                decoration: const InputDecoration(
                  labelText: 'Custodial group',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: groups
                    .map(
                      (group) => DropdownMenuItem<String>(
                        value: group.id,
                        child: Text(group.group.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: onSelectedGroupChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: CoolAsyncView<MomoStatementPage<PayeePaymentLedgerEntry>>(
            value: ledgerAsync,
            onRetry: onRetry,
            emptyCheck: (page) => page.entries.isEmpty,
            emptyWidget: const CoolEmptyView(
              message:
                  'No posted ledger entries are visible for the selected group yet.',
              compact: true,
            ),
            builder: (page) => Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed:
                        isExporting ||
                            onExportExcel == null ||
                            page.entries.isEmpty
                        ? null
                        : () => onExportExcel!(page.entries),
                    icon: isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.table_view_rounded),
                    label: Text(isExporting ? 'Exporting...' : 'Export Excel'),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: page.entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = page.entries[index];
                      return _LedgerEntryCard(entry: entry);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LedgerEntryCard extends StatelessWidget {
  const _LedgerEntryCard({required this.entry});

  final PayeePaymentLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    return CoolCard(
      backgroundColor: AppColors.surface,
      borderColor: AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.payerName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(entry.occurredAt),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${moneyFormat.format(entry.amount)} ${entry.currency}',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(label: 'Category', value: _title(entry.txCategory)),
              _InfoPill(label: 'Bucket', value: _title(entry.cashflowBucket)),
              _InfoPill(label: 'Target', value: _title(entry.targetTable)),
              _InfoPill(
                label: 'Reference',
                value: entry.reference?.trim().isNotEmpty == true
                    ? entry.reference!
                    : '-',
              ),
            ],
          ),
          if ((entry.payerPhone?.trim().isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            Text(
              'Phone: ${entry.payerPhone}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllocationsTab extends StatelessWidget {
  const _AllocationsTab({
    required this.items,
    required this.totalCount,
    required this.activeReviewId,
    required this.activeAction,
    required this.onAllocate,
    required this.onReject,
  });

  final List<BankAdminAllocationReviewItem> items;
  final int totalCount;
  final String? activeReviewId;
  final String? activeAction;
  final ValueChanged<BankAdminAllocationReviewItem> onAllocate;
  final ValueChanged<BankAdminAllocationReviewItem> onReject;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    if (items.isEmpty) {
      return const CoolEmptyView(
        message:
            'No unresolved allocations are currently queued for this bank.',
        compact: true,
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return CoolCard(
          backgroundColor: AppColors.surface,
          borderColor: AppColors.border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.groupName,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  _StatusTag(
                    label: _title(item.matchStatus),
                    backgroundColor: AppColors.orange.withValues(alpha: 0.12),
                    foregroundColor: AppColors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.payerName,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${moneyFormat.format(item.amount)} RWF',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Reason: ${_title(item.reason)}',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
              if ((item.reference?.trim().isNotEmpty ?? false))
                Text(
                  'Reference: ${item.reference}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
              if ((item.payeeDigits?.trim().isNotEmpty ?? false))
                Text(
                  'Payee route: ${item.payeeDigits}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: activeReviewId == item.reviewId
                        ? null
                        : () => onAllocate(item),
                    child: Text(
                      activeReviewId == item.reviewId &&
                              activeAction == 'allocate'
                          ? 'Allocating...'
                          : 'Allocate',
                    ),
                  ),
                  TextButton(
                    onPressed: activeReviewId == item.reviewId
                        ? null
                        : () => onReject(item),
                    child: Text(
                      activeReviewId == item.reviewId &&
                              activeAction == 'reject'
                          ? 'Rejecting...'
                          : 'Reject',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Updated ${dateFormat.format(item.updatedAt)}',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text3,
                ),
              ),
              if (index == 0 && totalCount > items.length) ...[
                const SizedBox(height: 10),
                Text(
                  'Showing ${items.length} of $totalCount unresolved items.',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

String _title(String raw) {
  if (raw.trim().isEmpty) {
    return '-';
  }
  return raw
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _fileSafe(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
