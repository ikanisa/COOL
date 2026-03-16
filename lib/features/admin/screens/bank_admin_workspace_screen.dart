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
  String _groupSearch = '';
  String _contribStatusFilter = 'all';
  String? _contribGroupFilter;
  String _loanStatusFilter = 'all';
  String _basketStatusFilter = 'all';
  String _allocationStatusFilter = 'all';
  bool _isAiRunning = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
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
              group.group.momoNumber ??
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
          'This will remove the',
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

  Future<void> _acceptSuggestion(BankAdminAllocationReviewItem item) async {
    if (_activeReviewId != null) return;
    setState(() {
      _activeReviewId = item.reviewId;
      _activeReviewAction = 'accept';
    });
    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.acceptSuggestedAllocation(
        partnerId: widget.partnerId,
        reviewId: item.reviewId,
      );
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      if (mounted) {
        CoolToast.success(context, 'AI suggestion accepted — payment allocated.');
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'Could not accept suggestion.');
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

  Future<void> _triggerAiAllocation() async {
    if (_isAiRunning) return;
    setState(() => _isAiRunning = true);
    try {
      final repository = ref.read(bankAdminRepositoryProvider);
      await repository.triggerAiAllocation(widget.partnerId);
      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
      if (mounted) {
        CoolToast.success(context, 'AI allocation complete — check suggestions.');
      }
    } catch (_) {
      if (mounted) {
        CoolToast.error(context, 'AI allocation failed.');
      }
    } finally {
      if (mounted) {
        setState(() => _isAiRunning = false);
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

    // If AI suggestion exists, prefer suggested group
    if (item.isSuggested && item.suggestedGroupId != null) {
      final suggestedExists = groups.any((g) => g.id == item.suggestedGroupId);
      if (suggestedExists) {
        selectedGroupId = item.suggestedGroupId!;
      }
    }

    List<BankAdminMemberRecord> membersFor(String groupId) {
      return snapshot.members.entries
          .where((member) => member.groupId == groupId)
          .toList(growable: false);
    }

    String? initialMemberId() {
      final scopedMembers = membersFor(selectedGroupId);
      if (scopedMembers.isEmpty) return null;
      // Prefer AI suggestion
      if (item.isSuggested && item.suggestedMemberUserId != null) {
        final match = scopedMembers.where(
          (m) => m.userId == item.suggestedMemberUserId,
        );
        if (match.isNotEmpty) return match.first.userId;
      }
      final matchedMember = scopedMembers.where(
        (member) => member.userId == item.payerUserId,
      );
      if (matchedMember.isNotEmpty) return matchedMember.first.userId;
      return scopedMembers.first.userId;
    }

    String? selectedMemberId = initialMemberId();
    String memberSearchQuery = '';
    bool showCreateMember = false;
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool isCreatingMember = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          var scopedMembers = membersFor(selectedGroupId);
          // Apply search filter
          if (memberSearchQuery.isNotEmpty) {
            final q = memberSearchQuery.toLowerCase();
            scopedMembers = scopedMembers
                .where((m) => m.displayName.toLowerCase().contains(q))
                .toList(growable: false);
          }
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
              child: SingleChildScrollView(
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
                    // ── AI suggestion banner ──
                    if (item.isSuggested) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
                                const SizedBox(width: 6),
                                Text(
                                  'AI Suggestion · ${(item.suggestedConfidence ?? 0).toStringAsFixed(0)}% match',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                            if (item.suggestedMemberName != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Suggested member: ${item.suggestedMemberName}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text2),
                              ),
                            ],
                            if (item.aiReasoning != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.aiReasoning!,
                                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // ── Group selector ──
                    DropdownButtonFormField<String>(
                      value: selectedGroupId,
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
                        if (value == null) return;
                        setModalState(() {
                          selectedGroupId = value;
                          memberSearchQuery = '';
                          final nextMembers = membersFor(value);
                          selectedMemberId = nextMembers.isEmpty
                              ? null
                              : nextMembers.first.userId;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    // ── Member search ──
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Search member',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: memberSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setModalState(() {
                                  memberSearchQuery = '';
                                }),
                              )
                            : null,
                      ),
                      onChanged: (v) => setModalState(() => memberSearchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    // ── Member dropdown ──
                    if (scopedMembers.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: selectedMemberId,
                        decoration: const InputDecoration(labelText: 'Member'),
                        items: scopedMembers
                            .map(
                              (member) => DropdownMenuItem<String>(
                                value: member.userId,
                                child: Text(member.displayName),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) =>
                            setModalState(() => selectedMemberId = value),
                      ),
                    if (scopedMembers.isEmpty && !showCreateMember) ...[
                      const SizedBox(height: 10),
                      Text(
                        memberSearchQuery.isNotEmpty
                            ? 'No members match "$memberSearchQuery"'
                            : 'No members in this group',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.orange,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // ── Create new member toggle ──
                    GestureDetector(
                      onTap: () => setModalState(() => showCreateMember = !showCreateMember),
                      child: Row(
                        children: [
                          Icon(
                            showCreateMember ? Icons.remove_circle_outline : Icons.add_circle_outline,
                            size: 18,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            showCreateMember ? 'Cancel new member' : 'Create new member',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Create member form ──
                    if (showCreateMember) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone number',
                          hintText: '07XXXXXXXX',
                          prefixIcon: Icon(Icons.phone, size: 18),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Display name (optional)',
                          prefixIcon: Icon(Icons.person, size: 18),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: isCreatingMember || phoneCtrl.text.trim().isEmpty
                              ? null
                              : () async {
                                  setModalState(() => isCreatingMember = true);
                                  try {
                                    final repo = ref.read(bankAdminRepositoryProvider);
                                    final result = await repo.addMemberToGroup(
                                      partnerId: widget.partnerId,
                                      groupId: selectedGroupId,
                                      phone: phoneCtrl.text.trim(),
                                      displayName: nameCtrl.text.trim().isEmpty
                                          ? null
                                          : nameCtrl.text.trim(),
                                    );
                                    final newUserId = result['member_user_id']?.toString();
                                    if (newUserId != null && newUserId.isNotEmpty) {
                                      // Refresh snapshot and allocate
                                      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
                                      if (mounted) {
                                        Navigator.of(context).pop();
                                        await _allocateManualReview(
                                          item: item,
                                          groupId: selectedGroupId,
                                          memberUserId: newUserId,
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      CoolToast.error(context, e.toString().replaceAll('Exception: ', ''));
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      setModalState(() => isCreatingMember = false);
                                    }
                                  }
                                },
                          icon: isCreatingMember
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.person_add, size: 18),
                          label: Text(isCreatingMember ? 'Creating...' : 'Add member & allocate'),
                        ),
                      ),
                    ],
                    if (!showCreateMember) ...[
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
                  ],
                ),
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

                    final analyticsAsync = ref.watch(
                      bankAnalyticsProvider(widget.partnerId),
                    );

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
                          analyticsAsync: analyticsAsync,
                        ),
                        const SizedBox(height: 24),
                        DecoratedBox(
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
                              Tab(text: 'Loans'),
                              Tab(text: 'Baskets'),
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
                                search: _groupSearch,
                                onSearchChanged: (v) => setState(() => _groupSearch = v),
                              ),
                              _MembersTab(
                                members: snapshot.members.entries,
                                totalCount: snapshot.members.totalCount,
                              ),
                              _ContributionsTab(
                                contributions: snapshot.contributions.entries,
                                totalCount: snapshot.contributions.totalCount,
                                statusFilter: _contribStatusFilter,
                                onStatusFilterChanged: (v) => setState(() => _contribStatusFilter = v),
                                groupFilter: _contribGroupFilter,
                                onGroupFilterChanged: (v) => setState(() => _contribGroupFilter = v),
                                groups: snapshot.groups.entries,
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
                                statusFilter: _allocationStatusFilter,
                                onStatusFilterChanged: (v) => setState(() => _allocationStatusFilter = v),
                                onAllocate: (item) =>
                                    _showAllocationSheet(item, snapshot),
                                onReject: _rejectManualReview,
                                onAcceptSuggestion: _acceptSuggestion,
                                onTriggerAi: _triggerAiAllocation,
                                isAiRunning: _isAiRunning,
                              ),
                              _LoansTab(
                                partnerId: widget.partnerId,
                                statusFilter: _loanStatusFilter,
                                onStatusFilterChanged: (v) => setState(() => _loanStatusFilter = v),
                              ),
                              _BasketsTab(
                                partnerId: widget.partnerId,
                                statusFilter: _basketStatusFilter,
                                onStatusFilterChanged: (v) => setState(() => _basketStatusFilter = v),
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
              message: 'The bank workspace could',
            ),
          ),
    );
  }
}

class _WorkspaceHero extends StatelessWidget {
  const _WorkspaceHero({
    required this.partnerName,
    required this.snapshot,
    required this.analyticsAsync,
  });

  final String partnerName;
  final BankAdminWorkspaceSnapshot snapshot;
  final AsyncValue<Map<String, dynamic>> analyticsAsync;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
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
            'Custodian workspace for group savings and loans.',
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
          analyticsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (data) {
              if (data.isEmpty) return const SizedBox.shrink();
              final totalAum = (data['total_aum'] as num?)?.toDouble() ?? 0;
              final loansOutstanding = (data['loans_outstanding'] as num?)?.toDouble() ?? 0;
              final activeBasketsCount = (data['active_baskets_count'] as num?)?.toInt() ?? 0;
              final activeLoansCount = (data['active_loans_count'] as num?)?.toInt() ?? 0;
              if (totalAum == 0 && loansOutstanding == 0 && activeBasketsCount == 0) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'Financial Summary',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricChip(
                        label: 'AUM',
                        value: '${moneyFormat.format(totalAum)} RWF',
                      ),
                      _MetricChip(
                        label: 'loans out',
                        value: '${moneyFormat.format(loansOutstanding)} RWF',
                      ),
                      _MetricChip(
                        label: 'active loans',
                        value: activeLoansCount.toString(),
                      ),
                      _MetricChip(
                        label: 'active baskets',
                        value: activeBasketsCount.toString(),
                      ),
                    ],
                  ),
                ],
              );
            },
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
    required this.search,
    required this.onSearchChanged,
  });

  final List<BankAdminGroupSummary> groups;
  final int totalCount;
  final ValueChanged<BankAdminGroupSummary> onOpenGroup;
  final ValueChanged<String> onOpenLedger;
  final String search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy');
    final lowerSearch = search.toLowerCase();
    final filtered = search.isEmpty
        ? groups
        : groups.where((g) => g.group.name.toLowerCase().contains(lowerSearch)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search groups...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        if (filtered.isEmpty)
          const Expanded(
            child: CoolEmptyView(
              message: 'No custodial groups found',
              compact: true,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = filtered[index];
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
                      if (index == 0 && totalCount > filtered.length) ...[
                        const SizedBox(height: 12),
                        Text(
                          '${filtered.length}/$totalCount shown',
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
            ),
          ),
      ],
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
                'Linked group profile active',
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
                  message: 'No member records are',
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
                            const _StatusTag(
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
                      'No contribution records are',
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
        message: 'No members are visible',
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
                const _StatusTag(
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
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.groupFilter,
    required this.onGroupFilterChanged,
    required this.groups,
  });

  final List<BankAdminContributionRecord> contributions;
  final int totalCount;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;
  final String? groupFilter;
  final ValueChanged<String?> onGroupFilterChanged;
  final List<BankAdminGroupSummary> groups;

  static const _statuses = ['all', 'confirmed', 'pending'];

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    var filtered = contributions;
    if (statusFilter != 'all') {
      filtered = filtered.where((c) => c.status == statusFilter).toList();
    }
    if (groupFilter != null && groupFilter!.isNotEmpty) {
      filtered = filtered.where((c) => c.groupId == groupFilter).toList();
    }

    return Column(
      children: [
        // Status filter chips
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _statuses.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final status = _statuses[index];
              final isActive = status == statusFilter;
              return FilterChip(
                label: Text(_title(status)),
                selected: isActive,
                onSelected: (_) => onStatusFilterChanged(status),
                backgroundColor: AppColors.surface2,
                selectedColor: AppColors.accent.withValues(alpha: 0.15),
                labelStyle: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.accent : AppColors.text2,
                ),
              );
            },
          ),
        ),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: groupFilter,
            decoration: const InputDecoration(
              labelText: 'Filter by group',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All groups')),
              ...groups.map((g) => DropdownMenuItem<String?>(
                value: g.id,
                child: Text(g.group.name),
              )),
            ],
            onChanged: onGroupFilterChanged,
          ),
        ],
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Expanded(
            child: CoolEmptyView(
              message: 'No contributions match the selected filters',
              compact: true,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final contribution = filtered[index];
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
            ),
          ),
      ],
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
        message: 'Link at least one',
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
                'Select a group to',
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
                  'No posted ledger entries',
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
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.onAllocate,
    required this.onReject,
    required this.onAcceptSuggestion,
    required this.onTriggerAi,
    required this.isAiRunning,
  });

  final List<BankAdminAllocationReviewItem> items;
  final int totalCount;
  final String? activeReviewId;
  final String? activeAction;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;
  final ValueChanged<BankAdminAllocationReviewItem> onAllocate;
  final ValueChanged<BankAdminAllocationReviewItem> onReject;
  final ValueChanged<BankAdminAllocationReviewItem> onAcceptSuggestion;
  final VoidCallback onTriggerAi;
  final bool isAiRunning;

  static const _filters = [
    ('all', 'All'),
    ('suggested', 'Suggested'),
    ('manual_review', 'Manual'),
    ('pending_review', 'Pending'),
    ('rejected', 'Rejected'),
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'suggested':
        return const Color(0xFF6366F1); // indigo
      case 'manual_review':
        return AppColors.orange;
      case 'pending_review':
        return AppColors.yellow;
      case 'rejected':
        return AppColors.red;
      case 'matched':
        return AppColors.accent;
      default:
        return AppColors.text3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    final filtered = statusFilter == 'all'
        ? items
        : items.where((i) => i.matchStatus == statusFilter).toList();

    return Stack(
      children: [
        Column(
          children: [
            // ── Status filter chips ──
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final (value, label) = _filters[index];
                  final selected = statusFilter == value;
                  final count = value == 'all'
                      ? items.length
                      : items.where((i) => i.matchStatus == value).length;
                  return FilterChip(
                    label: Text('$label${count > 0 ? ' ($count)' : ''}'),
                    selected: selected,
                    onSelected: (_) => onStatusFilterChanged(value),
                    backgroundColor: AppColors.surface,
                    selectedColor: AppColors.accent.withValues(alpha: 0.12),
                    labelStyle: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.accent : AppColors.text2,
                    ),
                    side: BorderSide(
                      color: selected ? AppColors.accent : AppColors.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // ── List ──
            Expanded(
              child: filtered.isEmpty
                  ? CoolEmptyView(
                      message: statusFilter == 'all'
                          ? 'No unresolved allocations. Tap the AI button to run auto-matching.'
                          : 'No ${statusFilter.replaceAll('_', ' ')} allocations.',
                      compact: true,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isActive = activeReviewId == item.reviewId;
                        final color = _statusColor(item.matchStatus);

                        return CoolCard(
                          backgroundColor: AppColors.surface,
                          borderColor: item.isSuggested
                              ? const Color(0xFF6366F1).withValues(alpha: 0.3)
                              : AppColors.border,
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
                                    backgroundColor: color.withValues(alpha: 0.12),
                                    foregroundColor: color,
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
                                  'Payee: ${item.payeeDigits}',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.text2,
                                  ),
                                ),
                              // ── AI suggestion banner ──
                              if (item.isSuggested) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF6366F1)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          '→ ${item.suggestedMemberName ?? 'Suggested member'} · ${(item.suggestedConfidence ?? 0).toStringAsFixed(0)}%',
                                          style: GoogleFonts.dmSans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF6366F1),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.aiReasoning != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.aiReasoning!,
                                    style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.text3),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                              const SizedBox(height: 12),
                              // ── Action buttons ──
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (item.isSuggested)
                                    FilledButton.icon(
                                      onPressed: isActive ? null : () => onAcceptSuggestion(item),
                                      icon: isActive && activeAction == 'accept'
                                          ? const SizedBox(
                                              width: 14, height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2, color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.check, size: 16),
                                      label: Text(
                                        isActive && activeAction == 'accept'
                                            ? 'Accepting...'
                                            : 'Accept',
                                      ),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF6366F1),
                                        textStyle: GoogleFonts.dmSans(
                                          fontSize: 12, fontWeight: FontWeight.w600,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  OutlinedButton(
                                    onPressed: isActive ? null : () => onAllocate(item),
                                    child: Text(
                                      isActive && activeAction == 'allocate'
                                          ? 'Allocating...'
                                          : item.isSuggested
                                              ? 'Override'
                                              : 'Allocate',
                                    ),
                                  ),
                                  if (item.matchStatus != 'rejected')
                                    TextButton(
                                      onPressed: isActive ? null : () => onReject(item),
                                      child: Text(
                                        isActive && activeAction == 'reject'
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
                              if (index == 0 && totalCount > filtered.length) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '${filtered.length}/$totalCount shown',
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
                    ),
            ),
          ],
        ),
        // ── Run AI Allocation FAB ──
        Positioned(
          right: 12,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'ai_allocation',
            onPressed: isAiRunning ? null : onTriggerAi,
            backgroundColor: const Color(0xFF6366F1),
            icon: isAiRunning
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            label: Text(
              isAiRunning ? 'Running...' : 'Run AI',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
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

// ═══════════════════════════════════════════════════════════════
// Loans Tab
// ═══════════════════════════════════════════════════════════════

class _LoansTab extends ConsumerWidget {
  const _LoansTab({
    required this.partnerId,
    required this.statusFilter,
    required this.onStatusFilterChanged,
  });
  final String partnerId;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  static const _statuses = ['all', 'pending', 'approved', 'disbursed', 'repaying', 'completed', 'defaulted', 'rejected'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(bankLoansProvider(partnerId));
    final moneyFmt = NumberFormat.decimalPattern('en_US');

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _statuses.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final s = _statuses[index];
              final active = s == statusFilter;
              return FilterChip(
                label: Text(_title(s)),
                selected: active,
                onSelected: (_) => onStatusFilterChanged(s),
                backgroundColor: AppColors.surface2,
                selectedColor: AppColors.accent.withValues(alpha: 0.15),
                labelStyle: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.accent : AppColors.text2,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: loansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: \$e')),
            data: (loans) {
              final filtered = statusFilter == 'all'
                  ? loans
                  : loans.where((l) => (l['status']?.toString() ?? '') == statusFilter).toList();
              if (filtered.isEmpty) {
                return const CoolEmptyView(
                  message: 'No loans match filter',
                  compact: true,
                );
              }
        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final loan = filtered[index];
            final amount = (loan['amount'] as num?)?.toDouble() ?? 0;
            final repaid = (loan['repaid_amount'] as num?)?.toDouble() ?? 0;
            final status = loan['status']?.toString() ?? 'pending';
            final memberName = loan['member_name']?.toString() ?? '—';
            final groupName = loan['group_name']?.toString() ?? '—';

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
                          memberName,
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      _StatusTag(
                        label: _title(status),
                        backgroundColor: _loanStatusColor(status).withValues(alpha: 0.15),
                        foregroundColor: _loanStatusColor(status),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    groupName,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _InfoPill(
                        label: 'Amount',
                        value: '${moneyFmt.format(amount)} RWF',
                      ),
                      const SizedBox(width: 8),
                      _InfoPill(
                        label: 'Repaid',
                        value: '${moneyFmt.format(repaid)} RWF',
                      ),
                    ],
                  ),
                  if (status == 'pending') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              await ref.read(bankAdminRepositoryProvider).updateLoanStatus(
                                loanId: loan['id'].toString(),
                                status: 'approved',
                              );
                              ref.invalidate(bankLoansProvider(partnerId));
                            },
                            child: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await ref.read(bankAdminRepositoryProvider).updateLoanStatus(
                                loanId: loan['id'].toString(),
                                status: 'rejected',
                              );
                              ref.invalidate(bankLoansProvider(partnerId));
                            },
                            child: const Text('Reject'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (status == 'approved') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.send_rounded, size: 16),
                        onPressed: () async {
                          await ref.read(bankAdminRepositoryProvider).updateLoanStatus(
                            loanId: loan['id'].toString(),
                            status: 'disbursed',
                          );
                          ref.invalidate(bankLoansProvider(partnerId));
                        },
                        label: const Text('Mark Disbursed'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    ),
  ),
],
);
  }
}

Color _loanStatusColor(String status) {
  switch (status) {
    case 'approved':
    case 'completed':
      return Colors.green;
    case 'disbursed':
    case 'repaying':
      return Colors.blue;
    case 'defaulted':
      return Colors.red;
    case 'rejected':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

// ═══════════════════════════════════════════════════════════════
// Baskets Tab
// ═══════════════════════════════════════════════════════════════

class _BasketsTab extends ConsumerWidget {
  const _BasketsTab({
    required this.partnerId,
    required this.statusFilter,
    required this.onStatusFilterChanged,
  });
  final String partnerId;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  static const _statuses = ['all', 'active', 'completed', 'closed'];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basketsAsync = ref.watch(bankBasketsProvider(partnerId));
    final moneyFmt = NumberFormat.decimalPattern('en_US');

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _statuses.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final s = _statuses[index];
              final active = s == statusFilter;
              return FilterChip(
                label: Text(_title(s)),
                selected: active,
                onSelected: (_) => onStatusFilterChanged(s),
                backgroundColor: AppColors.surface2,
                selectedColor: AppColors.accent.withValues(alpha: 0.15),
                labelStyle: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.accent : AppColors.text2,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: basketsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (baskets) {
              final filtered = statusFilter == 'all'
                  ? baskets
                  : baskets.where((b) => (b['status']?.toString() ?? '') == statusFilter).toList();
              if (filtered.isEmpty) {
                return const CoolEmptyView(
                  message: 'No baskets match filter',
                  compact: true,
                );
              }
        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final basket = filtered[index];
            final name = basket['name']?.toString() ?? 'Basket';
            final groupName = basket['group_name']?.toString() ?? '—';
            final targetAmount = (basket['target_amount'] as num?)?.toDouble() ?? 0;
            final currentAmount = (basket['current_amount'] as num?)?.toDouble() ?? 0;
            final progressPct = (basket['progress_pct'] as num?)?.toDouble() ?? 0;
            final status = basket['status']?.toString() ?? 'active';

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
                          name,
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      _StatusTag(
                        label: _title(status),
                        backgroundColor: status == 'completed'
                            ? Colors.green.withValues(alpha: 0.15)
                            : AppColors.surface2,
                        foregroundColor: status == 'completed'
                            ? Colors.green
                            : AppColors.text3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    groupName,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.text3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (progressPct / 100).clamp(0.0, 1.0),
                      backgroundColor: AppColors.surface2,
                      color: progressPct >= 100 ? Colors.green : AppColors.blue,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${moneyFmt.format(currentAmount)} / ${moneyFmt.format(targetAmount)} RWF',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text2,
                        ),
                      ),
                      Text(
                        '${progressPct.toStringAsFixed(1)}%',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: progressPct >= 100 ? Colors.green : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
            },
          ),
        ),
      ],
    );
  }
}
