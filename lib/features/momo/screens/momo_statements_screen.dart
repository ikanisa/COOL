import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/intl_locale.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/app_lifecycle_providers.dart';
import '../../profile/widgets/profile_app_access_sheet.dart';
import '../models/momo_statement.dart';
import '../models/momo_statement_filters.dart';
import '../providers/momo_sms_sync_providers.dart';
import '../providers/momo_statement_providers.dart';
import '../services/momo_sms_autoread_service.dart';
import '../services/momo_statement_export_service.dart';
import '../widgets/momo_sms_sync_status_card.dart';

part '../controllers/momo_statements_controller.dart';
part '../widgets/momo_statements_sections.dart';

class MomoStatementsScreen extends ConsumerStatefulWidget {
  const MomoStatementsScreen({super.key});

  @override
  ConsumerState<MomoStatementsScreen> createState() =>
      _MomoStatementsScreenState();
}

class _MomoStatementsScreenState extends ConsumerState<MomoStatementsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  StatementPeriodPreset _periodPreset = StatementPeriodPreset.month;
  StatementSortOption _sortOption = StatementSortOption.newestFirst;
  String? _selectedParty;
  DateTime? _customStartDate;
  DateTime? _customEndDate;
  bool _isExporting = false;
  bool _isSyncing = false;

  bool get _isWalletTab => _tabController.index == 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      setState(() => _selectedParty = null);
    }
  }

  void _closeOrReturnHome() {
    if (context.canPop()) {
      context.pop();
      return;
    }

    context.go(AppRoutes.home);
  }

  void _refresh() {
    ref.invalidate(momoStatementBundleProvider(_query));
  }

  void _applyState(VoidCallback update) {
    if (!mounted) {
      return;
    }
    setState(update);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;
    final theme = Theme.of(context);
    final showHeroTitle = MediaQuery.sizeOf(context).height >= 820;
    final moneyFormat = decimalMoneyFormatForLocale(context);
    final dateFormat = safeDateFormat('dd MMM yyyy');
    final dateTimeFormat = safeDateFormat('dd MMM yyyy, HH:mm');
    final bundleAsync = ref.watch(momoStatementBundleProvider(_query));

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
        ),
        title: Text(
          context.l10n.statements,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primaryText,
          ),
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.home,
            onPressed: () => context.go(AppRoutes.home),
            icon: Icon(Icons.home_rounded, color: colors.primaryText),
          ),
          IconButton(
            tooltip: context.l10n.syncSms,
            onPressed: _isSyncing ? null : _syncSms,
            icon: _isSyncing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.tertiaryText,
                    ),
                  )
                : Icon(Icons.sms_rounded, color: colors.primaryText),
          ),
          IconButton(
            tooltip: context.l10n.momoRefreshStatements,
            onPressed: _refresh,
            icon: Icon(Icons.refresh_rounded, color: colors.primaryText),
          ),
        ],
      ),
      body: CoolScreenBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                space.x3,
                0,
                space.x3,
                showHeroTitle ? space.x4 : space.x2,
              ),
              child: Text(
                context.l10n.momoStatementsTitle,
                style:
                    (showHeroTitle
                            ? theme.textTheme.displaySmall
                            : theme.textTheme.titleLarge)
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                          height: showHeroTitle ? 1.1 : 1.2,
                        ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                space.x3,
                0,
                space.x3,
                showHeroTitle ? space.x2 : space.x1,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.md),
                  ),
                  border: Border.all(color: colors.border),
                ),
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.sm),
                    ),
                    color: colors.cardSurfaceStrong,
                  ),
                  labelColor: colors.primaryText,
                  unselectedLabelColor: colors.tertiaryText,
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: [
                    Tab(
                      icon: const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 20,
                      ),
                      text: context.l10n.walletLabel,
                    ),
                    Tab(
                      icon: const Icon(Icons.savings_rounded, size: 20),
                      text: context.l10n.savingsLabel,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: CoolAsyncView<MomoStatementBundle>(
                value: bundleAsync,
                onRetry: _refresh,
                loadingWidget: const SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    CoolSpace.x4,
                    CoolSpace.x3,
                    CoolSpace.x4,
                    CoolSpace.x4,
                  ),
                  child: CoolSkeletonList(itemCount: 4),
                ),
                builder: (bundle) {
                  final viewModel = _buildViewModel(bundle);
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final showSyncStatus = constraints.maxHeight >= 620;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          CoolSpace.x3,
                          CoolSpace.x2,
                          CoolSpace.x3,
                          CoolSpace.x3,
                        ),
                        child: Column(
                          children: [
                            StatementOverviewCard(
                              selectedPeriod: _periodPreset,
                              periodSummary: _periodLabel(dateFormat),
                              optionsSummary: _optionsSummary(
                                viewModel.effectivePartyFilter,
                              ),
                              netBalance: _walletNetBalance(
                                bundle.walletEntries,
                              ),
                              inflow: _walletInflow(bundle.walletEntries),
                              outflow: _walletOutflow(bundle.walletEntries),
                              savingsTotal: _confirmedSavingsTotal(
                                bundle.savingsEntries,
                              ),
                              onSelectPeriod: _selectPeriod,
                              onOpenOptions: () => _showOptionsSheet(
                                viewModel: viewModel,
                                walletEntries: viewModel.filteredWalletEntries,
                                savingsEntries:
                                    viewModel.filteredSavingsEntries,
                              ),
                            ),
                            SizedBox(
                              height: showSyncStatus
                                  ? CoolSpace.x3
                                  : CoolSpace.x2,
                            ),
                            if (showSyncStatus) ...[
                              MomoSmsSyncStatusCard(
                                compact: true,
                                onManageAccess: () =>
                                    ProfileAppAccessSheet.show(context),
                                onSyncComplete: (_) => _refresh(),
                              ),
                              const SizedBox(height: CoolSpace.x4),
                            ],
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  WalletStatementTab(
                                    entries: viewModel.filteredWalletEntries,
                                    totalCount: bundle.walletTotalCount,
                                    dateFormat: dateTimeFormat,
                                    moneyFormat: moneyFormat,
                                    isFilteredView:
                                        viewModel.effectivePartyFilter != null,
                                  ),
                                  SavingsStatementTab(
                                    entries: viewModel.filteredSavingsEntries,
                                    totalCount: bundle.savingsTotalCount,
                                    dateFormat: dateFormat,
                                    moneyFormat: moneyFormat,
                                    isFilteredView:
                                        viewModel.effectivePartyFilter != null,
                                  ),
                                ],
                              ),
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
        ),
      ),
    );
  }
}

int _walletNetBalance(List<MomoWalletEntry> entries) {
  var value = 0;
  for (final entry in entries) {
    value += entry.isCredit ? entry.amount : -entry.amount;
  }
  return value;
}

int _walletInflow(List<MomoWalletEntry> entries) {
  return entries
      .where((entry) => entry.isCredit)
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

int _walletOutflow(List<MomoWalletEntry> entries) {
  return entries
      .where((entry) => entry.isDebit)
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}

int _confirmedSavingsTotal(List<SavingsStatementEntry> entries) {
  return entries
      .where((entry) => entry.isConfirmed)
      .fold<int>(0, (sum, entry) => sum + entry.amount);
}
