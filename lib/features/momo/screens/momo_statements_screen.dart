import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/intl_locale.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
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
    final palette = context.coolPalette;
    final moneyFormat = decimalMoneyFormatForLocale(context);
    final dateFormat = safeDateFormat('dd MMM yyyy');
    final dateTimeFormat = safeDateFormat('dd MMM yyyy, HH:mm');
    final bundleAsync = ref.watch(momoStatementBundleProvider(_query));

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: _closeOrReturnHome,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () => context.go(AppRoutes.home),
            icon: Icon(Icons.home_rounded, color: palette.text),
          ),
          IconButton(
            tooltip: l10n.momoRefreshStatements,
            onPressed: _refresh,
            icon: Icon(Icons.refresh_rounded, color: palette.text),
          ),
        ],
      ),
      body: CoolScreenBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Text(
                l10n.momoStatementsTitle,
                style: GoogleFonts.dmSans(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                  height: 1.1,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.border),
                ),
                child: TabBar(
                  controller: _tabController,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: palette.surface2,
                  ),
                  labelColor: palette.text,
                  unselectedLabelColor: palette.text3,
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
            Expanded(
              child: CoolAsyncView<MomoStatementBundle>(
                value: bundleAsync,
                onRetry: _refresh,
                loadingWidget: const SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: CoolSkeletonList(itemCount: 4),
                ),
                builder: (bundle) {
                  final viewModel = _buildViewModel(bundle);
                  final visibleCount = _isWalletTab
                      ? viewModel.filteredWalletEntries.length
                      : viewModel.filteredSavingsEntries.length;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        StatementOverviewCard(
                          title: _isWalletTab
                              ? l10n.walletLedgerTitle
                              : l10n.savingsStatementTitle,
                          headlineValue: '$visibleCount',
                          headlineLabel: _isWalletTab
                              ? visibleCount == 1
                                    ? 'wallet entry in view'
                                    : 'wallet entries in view'
                              : visibleCount == 1
                              ? 'savings entry in view'
                              : 'savings entries in view',
                          supportingLabel: _periodLabel(dateFormat),
                          primaryMetricLabel: _isWalletTab
                              ? l10n.incomingLabel
                              : 'Saved',
                          primaryMetricValue: _isWalletTab
                              ? moneyFormat.format(viewModel.incomingTotal)
                              : moneyFormat.format(viewModel.savingsTotal),
                          secondaryMetricLabel: _isWalletTab
                              ? l10n.outgoingLabel
                              : l10n.navGroups,
                          secondaryMetricValue: _isWalletTab
                              ? moneyFormat.format(viewModel.outgoingTotal)
                              : '${viewModel.activeSavingsGroups}',
                        ),
                        const SizedBox(height: 12),
                        StatementToolbarCard(
                          selectedPeriod: _periodPreset,
                          periodSummary: _periodLabel(dateFormat),
                          optionsSummary: _optionsSummary(
                            viewModel.effectivePartyFilter,
                          ),
                          onSelectPeriod: _selectPeriod,
                          onOpenOptions: () => _showOptionsSheet(
                            viewModel: viewModel,
                            walletEntries: viewModel.filteredWalletEntries,
                            savingsEntries: viewModel.filteredSavingsEntries,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
