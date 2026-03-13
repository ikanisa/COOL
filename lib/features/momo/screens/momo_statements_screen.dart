import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/intl_locale.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_state_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/momo_statement.dart';
import '../models/momo_statement_filters.dart';
import '../providers/momo_statement_providers.dart';
import '../services/momo_statement_export_service.dart';

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
    final l10n = context.l10n;
    final locale = Localizations.maybeLocaleOf(context);
    final moneyFormat = decimalMoneyFormatForLocale(context);
    final dateFormat = safeDateFormat('dd MMM yyyy', locale: locale);
    final dateTimeFormat = safeDateFormat('dd MMM yyyy, HH:mm', locale: locale);
    final user = ref.watch(authProvider).user;
    final bundleAsync = ref.watch(momoStatementBundleProvider(_query));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: _closeOrReturnHome,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          l10n.momoStatementsTitle,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () => context.go(AppRoutes.home),
            icon: const Icon(Icons.home_rounded, color: AppColors.text),
          ),
          IconButton(
            tooltip: l10n.momoRefreshStatements,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.text),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.surface2,
              ),
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.text3,
              labelStyle: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                Tab(text: l10n.walletLabel),
                Tab(text: l10n.savingsLabel),
              ],
            ),
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: CoolAsyncView<MomoStatementBundle>(
          value: bundleAsync,
          onRetry: _refresh,
          builder: (bundle) {
            final viewModel = _buildViewModel(bundle);
            return LayoutBuilder(
              builder: (context, constraints) {
                final topMaxHeight = constraints.maxHeight < 620
                    ? constraints.maxHeight * 0.44
                    : 320.0;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: topMaxHeight),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              StatementOverviewCard(
                                userName:
                                    user?.fullName ?? l10n.coolMemberFallback,
                                officialPhone:
                                    user?.officialPhone ?? user?.phone ?? '-',
                                periodLabel: _periodLabel(dateFormat),
                                walletCount: viewModel.filteredWalletEntries.length,
                                savingsCount:
                                    viewModel.filteredSavingsEntries.length,
                                incomingTotal: viewModel.incomingTotal,
                                outgoingTotal: viewModel.outgoingTotal,
                                moneyFormat: moneyFormat,
                              ),
                              const SizedBox(height: 12),
                              StatementControlsCard(
                                selectedPeriod: _periodPreset,
                                selectedParty: viewModel.effectivePartyFilter,
                                selectedSort: _sortOption,
                                activePartyLabel: _activePartyLabel(),
                                allPartyLabel: _allPartyLabel(),
                                partyOptions: viewModel.activePartyOptions,
                                customPeriodLabel:
                                    _periodPreset ==
                                        StatementPeriodPreset.custom
                                    ? _periodLabel(dateFormat)
                                    : null,
                                isExporting: _isExporting,
                                canExport: _isWalletTab
                                    ? viewModel.filteredWalletEntries.isNotEmpty
                                    : viewModel.filteredSavingsEntries.isNotEmpty,
                                onSelectPeriod: _selectPeriod,
                                onPartyChanged: (value) {
                                  setState(() => _selectedParty = value);
                                },
                                onSortChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  setState(() => _sortOption = value);
                                },
                                onReset: _resetFilters,
                                onDownloadPdf: () => _downloadActiveStatement(
                                  format: StatementExportFormat.pdf,
                                  walletEntries: viewModel.filteredWalletEntries,
                                  savingsEntries:
                                      viewModel.filteredSavingsEntries,
                                ),
                                onDownloadExcel: () => _downloadActiveStatement(
                                  format: StatementExportFormat.excel,
                                  walletEntries: viewModel.filteredWalletEntries,
                                  savingsEntries:
                                      viewModel.filteredSavingsEntries,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
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
    );
  }
}
