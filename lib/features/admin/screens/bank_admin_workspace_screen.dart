import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../momo/models/momo_statement.dart';
import '../../momo/providers/momo_statement_providers.dart';
import '../../momo/services/momo_statement_export_service.dart';
import '../../partners/providers/partner_provider.dart';
import '../models/bank_admin_models.dart';
import '../providers/bank_admin_providers.dart';
import '../widgets/admin_workspace_gate.dart';
import '../widgets/bank_admin/bank_admin_helpers.dart';
import '../widgets/bank_admin/bank_allocations_tab.dart';
import '../widgets/bank_admin/bank_baskets_tab.dart';
import '../widgets/bank_admin/bank_contributions_tab.dart';
import '../widgets/bank_admin/bank_groups_tab.dart';
import '../widgets/bank_admin/bank_ledgers_tab.dart';
import '../widgets/bank_admin/bank_loans_tab.dart';
import '../widgets/bank_admin/bank_members_tab.dart';
import '../widgets/bank_admin/bank_workspace_hero.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_screen_background.dart';

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
    showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => BankGroupDetailSheet(
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
    required StatementExportFormat format,
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
        format: format,
        entries: entries,
        metadata: StatementExportMetadata(
          statementTitle: '${group.group.name} payment ledger',
          fileStem:
              'bank_${bankFileSafe(partnerName)}_${bankFileSafe(group.group.name)}_ledger',
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
        title: Text(context.l10n.rejectAllocation),
        content: const Text(
          'This will remove the',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.reject),
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

    await showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final palette = context.coolPalette;
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
                          color: palette.border,
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
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${NumberFormat.decimalPattern('en_US').format(item.amount)} RWF · ${item.groupName}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: palette.text2,
                      ),
                    ),
                    // ── AI suggestion banner ──
                    if (item.isSuggested) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: palette.accent.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.auto_awesome, size: 16, color: palette.accent),
                                const SizedBox(width: 6),
                                Text(
                                  'AI Suggestion · ${(item.suggestedConfidence ?? 0).toStringAsFixed(0)}% match',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: palette.accent,
                                  ),
                                ),
                              ],
                            ),
                            if (item.suggestedMemberName != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Suggested member: ${item.suggestedMemberName}',
                                style: GoogleFonts.dmSans(fontSize: 12, color: palette.text2),
                              ),
                            ],
                            if (item.aiReasoning != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.aiReasoning!,
                                style: GoogleFonts.dmSans(fontSize: 11, color: palette.text3),
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
                                tooltip: 'Clear',
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
                          color: palette.orange,
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
                            color: palette.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            showCreateMember ? 'Cancel new member' : 'Create new member',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: palette.accent,
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
                                      ref.invalidate(bankAdminWorkspaceProvider(widget.partnerId));
                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                        await _allocateManualReview(
                                          item: item,
                                          groupId: selectedGroupId,
                                          memberUserId: newUserId,
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
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
                          child: Text(context.l10n.allocateToMember),
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

              return CoolScreenBackground(


                showGlow: false,


                child: Scaffold(
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
                          '$partnerName Terminal',
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        const SizedBox(height: 24),
                        BankWorkspaceHero(
                          partnerName: partnerName,
                          snapshot: snapshot,
                          analyticsAsync: analyticsAsync,
                        ),
                        const SizedBox(height: 32),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: palette.surface2,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: palette.border, width: 1.5),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            labelColor: Colors.white,
                            unselectedLabelColor: palette.text3,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: palette.blue,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                            unselectedLabelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.all(4),
                            tabs: const [
                              Tab(text: 'GROUPS', height: 40),
                              Tab(text: 'MEMBERS', height: 40),
                              Tab(text: 'CONTRIBUTIONS', height: 40),
                              Tab(text: 'LEDGERS', height: 40),
                              Tab(text: 'ALLOCATIONS', height: 40),
                              Tab(text: 'LOANS', height: 40),
                              Tab(text: 'BASKETS', height: 40),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 600,
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              BankGroupsTab(
                                groups: snapshot.groups.entries,
                                totalCount: snapshot.groups.totalCount,
                                onOpenGroup: (group) =>
                                    _openGroupDetail(group, snapshot),
                                onOpenLedger: _openLedgerTab,
                                search: _groupSearch,
                                onSearchChanged: (v) => setState(() => _groupSearch = v),
                              ),
                              BankMembersTab(
                                members: snapshot.members.entries,
                                totalCount: snapshot.members.totalCount,
                              ),
                              BankContributionsTab(
                                contributions: snapshot.contributions.entries,
                                totalCount: snapshot.contributions.totalCount,
                                statusFilter: _contribStatusFilter,
                                onStatusFilterChanged: (v) => setState(() => _contribStatusFilter = v),
                                groupFilter: _contribGroupFilter,
                                onGroupFilterChanged: (v) => setState(() => _contribGroupFilter = v),
                                groups: snapshot.groups.entries,
                              ),
                              BankLedgersTab(
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
                                    onExport: selectedGroup == null
                                        ? null
                                        : (format, entries) => _exportLedger(
                                            format: format,
                                            partnerName: partnerName,
                                            group: selectedGroup,
                                            entries: entries,
                                          ),
                                    isExporting: _isExportingLedger,
                                  ),
                              BankAllocationsTab(
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
                              BankLoansTab(
                                partnerId: widget.partnerId,
                                statusFilter: _loanStatusFilter,
                                onStatusFilterChanged: (v) => setState(() => _loanStatusFilter = v),
                              ),
                              BankBasketsTab(
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