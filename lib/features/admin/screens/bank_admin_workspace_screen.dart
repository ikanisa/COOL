import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/cool_foundations.dart';
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

part '../widgets/bank_admin/bank_admin_workspace_parts.dart';

EdgeInsets _bankWorkspaceContentPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: CoolSpace.x7);

EdgeInsets _bankWorkspaceTabPadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x1,
  right: CoolSpace.x1,
  top: CoolSpace.x1,
  bottom: CoolSpace.x1,
);

const BorderRadius _bankWorkspaceTabsRadius = BorderRadius.all(
  Radius.circular(CoolRadii.sm),
);

const BorderRadius _bankWorkspaceTabIndicatorRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

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

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
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
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    iconTheme: IconThemeData(color: colors.primaryText),
                  ),
                  body: CoolAsyncView<BankAdminWorkspaceSnapshot>(
                    value: workspaceAsync,
                    onRetry: () => ref.invalidate(
                      bankAdminWorkspaceProvider(widget.partnerId),
                    ),
                    builder: (snapshot) {
                      this._syncSelectedGroup(snapshot.groups.entries);
                      final selectedGroup = this._selectedGroup(
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
                        padding: _bankWorkspaceContentPadding(),
                        children: [
                          Text(
                            '$partnerName Terminal',
                            style: theme.textTheme.displayLarge?.copyWith(
                              color: colors.primaryText,
                            ),
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
                              color: colors.operationalSurface,
                              borderRadius: _bankWorkspaceTabsRadius,
                              border: Border.all(
                                color: colors.border,
                                width: 1.5,
                              ),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              isScrollable: true,
                              labelColor: colors.accentForeground,
                              unselectedLabelColor: colors.tertiaryText,
                              indicatorSize: TabBarIndicatorSize.tab,
                              indicator: BoxDecoration(
                                color: colors.info,
                                borderRadius: _bankWorkspaceTabIndicatorRadius,
                              ),
                              labelStyle: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                              unselectedLabelStyle: theme.textTheme.labelSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              padding: _bankWorkspaceTabPadding(),
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
                                      this._openGroupDetail(group, snapshot),
                                  onOpenLedger: this._openLedgerTab,
                                  search: _groupSearch,
                                  onSearchChanged: (v) =>
                                      setState(() => _groupSearch = v),
                                ),
                                BankMembersTab(
                                  members: snapshot.members.entries,
                                  totalCount: snapshot.members.totalCount,
                                ),
                                BankContributionsTab(
                                  contributions: snapshot.contributions.entries,
                                  totalCount: snapshot.contributions.totalCount,
                                  statusFilter: _contribStatusFilter,
                                  onStatusFilterChanged: (v) =>
                                      setState(() => _contribStatusFilter = v),
                                  groupFilter: _contribGroupFilter,
                                  onGroupFilterChanged: (v) =>
                                      setState(() => _contribGroupFilter = v),
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
                                      : (format, entries) => this._exportLedger(
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
                                  onStatusFilterChanged: (v) => setState(
                                    () => _allocationStatusFilter = v,
                                  ),
                                  onAllocate: (item) =>
                                      this._showAllocationSheet(item, snapshot),
                                  onReject: this._rejectManualReview,
                                  onAcceptSuggestion: this._acceptSuggestion,
                                  onTriggerAi: this._triggerAiAllocation,
                                  isAiRunning: _isAiRunning,
                                ),
                                BankLoansTab(
                                  partnerId: widget.partnerId,
                                  statusFilter: _loanStatusFilter,
                                  onStatusFilterChanged: (v) =>
                                      setState(() => _loanStatusFilter = v),
                                ),
                                BankBasketsTab(
                                  partnerId: widget.partnerId,
                                  statusFilter: _basketStatusFilter,
                                  onStatusFilterChanged: (v) =>
                                      setState(() => _basketStatusFilter = v),
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
