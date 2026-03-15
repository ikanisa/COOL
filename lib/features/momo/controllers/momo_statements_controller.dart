part of '../screens/momo_statements_screen.dart';

class _MomoStatementsViewModel {
  const _MomoStatementsViewModel({
    required this.activePartyOptions,
    required this.effectivePartyFilter,
    required this.filteredWalletEntries,
    required this.filteredSavingsEntries,
    required this.incomingTotal,
    required this.outgoingTotal,
    required this.savingsTotal,
    required this.activeSavingsGroups,
  });

  final List<String> activePartyOptions;
  final String? effectivePartyFilter;
  final List<MomoWalletEntry> filteredWalletEntries;
  final List<SavingsStatementEntry> filteredSavingsEntries;
  final int incomingTotal;
  final int outgoingTotal;
  final int savingsTotal;
  final int activeSavingsGroups;
}

extension _MomoStatementsController on _MomoStatementsScreenState {
  StatementDateRange get _dateRange => resolveStatementDateRange(
    preset: _periodPreset,
    customStartDate: _customStartDate,
    customEndDate: _customEndDate,
  );

  MomoStatementQuery get _query {
    final dateRange = _dateRange;
    return MomoStatementQuery(
      startDate: dateRange.startDate,
      endDate: dateRange.endDate,
      limit: 5000,
    );
  }

  _MomoStatementsViewModel _buildViewModel(MomoStatementBundle bundle) {
    final activePartyOptions = _isWalletTab
        ? walletPartyOptions(bundle.walletEntries)
        : savingsPartyOptions(bundle.savingsEntries);
    final effectivePartyFilter = activePartyOptions.contains(_selectedParty)
        ? _selectedParty
        : null;
    final filteredWalletEntries = applyWalletStatementView(
      entries: bundle.walletEntries,
      partyFilter: _isWalletTab ? effectivePartyFilter : null,
      sortOption: _sortOption,
    );
    final filteredSavingsEntries = applySavingsStatementView(
      entries: bundle.savingsEntries,
      partyFilter: _isWalletTab ? null : effectivePartyFilter,
      sortOption: _sortOption,
    );

    return _MomoStatementsViewModel(
      activePartyOptions: activePartyOptions,
      effectivePartyFilter: effectivePartyFilter,
      filteredWalletEntries: filteredWalletEntries,
      filteredSavingsEntries: filteredSavingsEntries,
      incomingTotal: filteredWalletEntries
          .where((entry) => entry.isCredit)
          .fold<int>(0, (sum, entry) => sum + entry.amount),
      outgoingTotal: filteredWalletEntries
          .where((entry) => entry.isDebit)
          .fold<int>(0, (sum, entry) => sum + entry.amount),
      savingsTotal: filteredSavingsEntries.fold<int>(
        0,
        (sum, entry) => sum + entry.amount,
      ),
      activeSavingsGroups: filteredSavingsEntries
          .map((entry) => entry.groupId)
          .toSet()
          .length,
    );
  }

  String _activePartyLabel() {
    return _isWalletTab ? 'Payer' : context.l10n.navGroups;
  }

  String _allPartyLabel() {
    return _isWalletTab ? 'All payers' : 'All groups';
  }

  String _optionsSummary(String? effectivePartyFilter) {
    final audienceLabel = effectivePartyFilter == null
        ? _allPartyLabel()
        : '${_activePartyLabel()}: $effectivePartyFilter';
    return '$audienceLabel · ${_sortOptionLabel()}';
  }

  Future<void> _selectPeriod(StatementPeriodPreset preset) async {
    if (preset == StatementPeriodPreset.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _customStartDate != null && _customEndDate != null
            ? DateTimeRange(start: _customStartDate!, end: _customEndDate!)
            : null,
        helpText: 'Select custom period',
      );
      if (!mounted || picked == null) {
        return;
      }
      _applyState(() {
        _periodPreset = StatementPeriodPreset.custom;
        _customStartDate = DateUtils.dateOnly(picked.start);
        _customEndDate = DateUtils.dateOnly(picked.end);
        _selectedParty = null;
      });
      return;
    }

    _applyState(() {
      _periodPreset = preset;
      _selectedParty = null;
    });
  }

  void _resetFilters() {
    _applyState(() {
      _periodPreset = StatementPeriodPreset.month;
      _sortOption = StatementSortOption.newestFirst;
      _selectedParty = null;
      _customStartDate = null;
      _customEndDate = null;
    });
  }

  Future<void> _showOptionsSheet({
    required _MomoStatementsViewModel viewModel,
    required List<MomoWalletEntry> walletEntries,
    required List<SavingsStatementEntry> savingsEntries,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatementOptionsSheet(
          activePartyLabel: _activePartyLabel(),
          allPartyLabel: _allPartyLabel(),
          partyOptions: viewModel.activePartyOptions,
          initialParty: viewModel.effectivePartyFilter,
          initialSort: _sortOption,
          canExport: _isWalletTab
              ? walletEntries.isNotEmpty
              : savingsEntries.isNotEmpty,
          onApply: (party, sort) {
            _applyState(() {
              _selectedParty = party;
              _sortOption = sort;
            });
          },
          onReset: _resetFilters,
          onDownloadPdf: () => _downloadActiveStatement(
            format: StatementExportFormat.pdf,
            walletEntries: walletEntries,
            savingsEntries: savingsEntries,
          ),
          onDownloadExcel: () => _downloadActiveStatement(
            format: StatementExportFormat.excel,
            walletEntries: walletEntries,
            savingsEntries: savingsEntries,
          ),
        );
      },
    );
  }

  Future<void> _downloadActiveStatement({
    required StatementExportFormat format,
    required List<MomoWalletEntry> walletEntries,
    required List<SavingsStatementEntry> savingsEntries,
  }) async {
    if (_isExporting) {
      return;
    }

    final l10n = context.l10n;
    final activeWalletEntries = _isWalletTab
        ? walletEntries
        : const <MomoWalletEntry>[];
    final activeSavingsEntries = _isWalletTab
        ? const <SavingsStatementEntry>[]
        : savingsEntries;
    if (activeWalletEntries.isEmpty && activeSavingsEntries.isEmpty) {
      CoolToast.info(context, 'Nothing to download for the current filters.');
      return;
    }

    final user = ref.read(authProvider).user;
    final metadata = StatementExportMetadata(
      statementTitle: _isWalletTab
          ? l10n.walletLedgerTitle
          : l10n.savingsStatementTitle,
      fileStem: _isWalletTab ? 'cool_wallet_ledger' : 'cool_savings_statement',
      userName: user?.fullName ?? l10n.coolMemberFallback,
      officialPhone: user?.officialPhone ?? user?.phone ?? '',
      generatedAt: DateTime.now(),
      periodLabel: _periodLabel(DateFormat('dd MMM yyyy')),
      filterLabel: _filterSummaryLabel(),
      sortLabel: _sortOptionLabel(),
    );

    _applyState(() => _isExporting = true);
    try {
      final exportService = ref.read(momoStatementExportServiceProvider);
      final downloadService = ref.read(momoStatementDownloadServiceProvider);
      final export = _isWalletTab
          ? await exportService.buildWalletExport(
              format: format,
              entries: activeWalletEntries,
              metadata: metadata,
            )
          : await exportService.buildSavingsExport(
              format: format,
              entries: activeSavingsEntries,
              metadata: metadata,
            );
      final result = await downloadService.saveExport(export);
      if (!mounted) {
        return;
      }
      final message = result.usedSaveAs
          ? 'Saved ${result.fileName}'
          : 'Downloaded ${result.fileName}';
      CoolToast.success(context, message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Statement download failed.');
    } finally {
      if (mounted) {
        _applyState(() => _isExporting = false);
      }
    }
  }

  String _periodLabel(DateFormat dateFormat) {
    final range = _dateRange;
    final startDate = range.startDate;
    final endDate = range.endDate;
    if (startDate == null || endDate == null) {
      return context.l10n.allTimeLabel;
    }
    if (startDate == endDate) {
      return dateFormat.format(startDate);
    }
    return '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}';
  }

  String _filterSummaryLabel() {
    final parts = <String>['Period: ${_periodChipLabel(_periodPreset)}'];
    if (_selectedParty != null && _selectedParty!.trim().isNotEmpty) {
      parts.add('${_activePartyLabel()}: ${_selectedParty!.trim()}');
    } else {
      parts.add(_allPartyLabel());
    }
    return parts.join(' · ');
  }

  String _sortOptionLabel() {
    return switch (_sortOption) {
      StatementSortOption.newestFirst => 'Newest first',
      StatementSortOption.oldestFirst => 'Oldest first',
      StatementSortOption.amountHighToLow => 'Amount high to low',
      StatementSortOption.amountLowToHigh => 'Amount low to high',
      StatementSortOption.nameAz => 'Name A-Z',
      StatementSortOption.nameZa => 'Name Z-A',
    };
  }

  String _periodChipLabel(StatementPeriodPreset preset) {
    return switch (preset) {
      StatementPeriodPreset.day => 'Day',
      StatementPeriodPreset.week => 'Week',
      StatementPeriodPreset.month => 'Month',
      StatementPeriodPreset.year => 'Year',
      StatementPeriodPreset.custom => 'Custom',
      StatementPeriodPreset.all => 'All time',
    };
  }
}
