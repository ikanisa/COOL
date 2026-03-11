import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/momo_sms_history_store.dart';
import '../../../core/services/momo_sms_permission_service.dart';
import '../../../core/services/momo_sms_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_brand_mark.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/momo_statement.dart';
import '../providers/momo_sms_providers.dart';
import '../providers/momo_statement_providers.dart';
import '../services/momo_statement_export_service.dart';

enum _StatementTab { wallet, savings }

enum _WalletFilter { all, incoming, outgoing, savings, expense }

enum _SavingsFilter { all, confirmed, pending, failed }

enum _StatementSort { newest, oldest, amountHigh, amountLow }

class MomoSmsHistoryScreen extends ConsumerStatefulWidget {
  const MomoSmsHistoryScreen({super.key});

  @override
  ConsumerState<MomoSmsHistoryScreen> createState() =>
      _MomoSmsHistoryScreenState();
}

class _MomoSmsHistoryScreenState extends ConsumerState<MomoSmsHistoryScreen> {
  late final TextEditingController _searchController;
  final MomoStatementExportService _exportService =
      MomoStatementExportService();

  _StatementTab _activeTab = _StatementTab.wallet;
  _WalletFilter _walletFilter = _WalletFilter.all;
  _SavingsFilter _savingsFilter = _SavingsFilter.all;
  _StatementSort _sort = _StatementSort.newest;
  DateTimeRange? _statementRange;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim().toLowerCase();

  Future<void> _refresh() async {
    await ref.read(momoPaymentSyncProvider.notifier).retrySmsSetup();
    ref.invalidate(momoStatementBundleProvider);
    ref.invalidate(momoSmsHistoryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(momoPaymentSyncProvider);
    final statementAsync = ref.watch(momoStatementBundleProvider);
    final historyAsync = ref.watch(momoSmsHistoryProvider);
    final user = ref.watch(authProvider).user;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'M-Money Statements',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface2,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _StatusCard(state: syncState),
                  const SizedBox(height: 16),
                  _ActionCard(state: syncState),
                  const SizedBox(height: 22),
                  SectionTitle(
                    title: 'Statement Center',
                    actionLabel: 'Refresh',
                    onAction: () {
                      unawaited(_refresh());
                    },
                  ),
                  const SizedBox(height: 12),
                  statementAsync.when(
                    data: (bundle) {
                      final visibleWallet = _filterWalletEntries(
                        bundle.walletEntries,
                      );
                      final visibleSavings = _filterSavingsEntries(
                        bundle.savingsEntries,
                      );

                      return Column(
                        children: [
                          _StatementHeroCard(
                            userName:
                                user?.officialName?.trim().isNotEmpty == true
                                ? user!.officialName!.trim()
                                : (user?.fullName.isNotEmpty == true
                                      ? user!.fullName
                                      : 'COOL member'),
                            officialPhone:
                                user?.officialPhone?.trim().isNotEmpty == true
                                ? user!.officialPhone!.trim()
                                : (user?.phone ?? ''),
                            activeTab: _activeTab,
                            walletEntries: visibleWallet,
                            savingsEntries: visibleSavings,
                            periodLabel: _periodLabel,
                          ),
                          const SizedBox(height: 14),
                          _StatementTabSelector(
                            activeTab: _activeTab,
                            onChanged: (value) {
                              setState(() => _activeTab = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          _StatementSearchBar(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            hintText: _activeTab == _StatementTab.wallet
                                ? 'Search counterparty, reference, or category'
                                : 'Search group name or payment reference',
                          ),
                          const SizedBox(height: 12),
                          _StatementToolbar(
                            activeTab: _activeTab,
                            sort: _sort,
                            onSortChanged: (value) {
                              setState(() => _sort = value);
                            },
                            onExport: bundle.isEmpty
                                ? null
                                : () => _exportStatement(
                                    context,
                                    bundle: bundle,
                                    userName:
                                        user?.officialName?.trim().isNotEmpty ==
                                            true
                                        ? user!.officialName!.trim()
                                        : (user?.fullName.isNotEmpty == true
                                              ? user!.fullName
                                              : 'COOL member'),
                                    officialPhone:
                                        user?.officialPhone
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? user!.officialPhone!.trim()
                                        : (user?.phone ?? ''),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          _StatementRangeBar(
                            label: _periodLabel,
                            hasCustomRange: _statementRange != null,
                            onPickRange: () => _pickDateRange(context),
                            onClearRange: _statementRange == null
                                ? null
                                : () => setState(() => _statementRange = null),
                          ),
                          const SizedBox(height: 12),
                          if (_activeTab == _StatementTab.wallet)
                            _WalletFilterChips(
                              value: _walletFilter,
                              onChanged: (value) {
                                setState(() => _walletFilter = value);
                              },
                            )
                          else
                            _SavingsFilterChips(
                              value: _savingsFilter,
                              onChanged: (value) {
                                setState(() => _savingsFilter = value);
                              },
                            ),
                          const SizedBox(height: 14),
                          if (_activeTab == _StatementTab.wallet)
                            _WalletStatementList(entries: visibleWallet)
                          else
                            _SavingsStatementList(entries: visibleSavings),
                        ],
                      );
                    },
                    loading: () => const _StatementLoadingState(),
                    error: (error, _) => _HistoryErrorCard(
                      message: error.toString(),
                      onRetry: () {
                        ref.invalidate(momoStatementBundleProvider);
                      },
                      title: 'Unable to load statements',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SectionTitle(
                    title: 'Verification Audit',
                    actionLabel: 'Refresh',
                    onAction: () {
                      ref.invalidate(momoSmsHistoryProvider);
                    },
                  ),
                  const SizedBox(height: 12),
                  historyAsync.when(
                    data: (history) {
                      if (history.isEmpty) {
                        return const _EmptyHistoryCard();
                      }

                      return Column(
                        children: [
                          for (var i = 0; i < history.length; i++) ...[
                            _HistoryEntryCard(entry: history[i]),
                            if (i != history.length - 1)
                              const SizedBox(height: 12),
                          ],
                        ],
                      );
                    },
                    loading: () => const _HistoryLoadingList(),
                    error: (error, _) => _HistoryErrorCard(
                      message: error.toString(),
                      onRetry: () {
                        ref.invalidate(momoSmsHistoryProvider);
                      },
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<MomoWalletEntry> _filterWalletEntries(List<MomoWalletEntry> entries) {
    Iterable<MomoWalletEntry> visible = entries;

    visible = visible.where((entry) => _matchesSelectedRange(entry.occurredAt));

    switch (_walletFilter) {
      case _WalletFilter.all:
        break;
      case _WalletFilter.incoming:
        visible = visible.where((entry) => entry.isCredit);
      case _WalletFilter.outgoing:
        visible = visible.where((entry) => entry.isDebit);
      case _WalletFilter.savings:
        visible = visible.where(
          (entry) =>
              entry.cashflowBucket == 'savings' ||
              entry.txCategory == 'group_contribution',
        );
      case _WalletFilter.expense:
        visible = visible.where(
          (entry) =>
              entry.cashflowBucket == 'expense' ||
              entry.cashflowBucket == 'fees',
        );
    }

    if (_query.isNotEmpty) {
      visible = visible.where((entry) {
        final haystack = <String>[
          entry.label,
          entry.counterpartyName ?? '',
          entry.reference ?? '',
          entry.txCategory,
          entry.cashflowBucket,
          entry.description ?? '',
        ].join(' ').toLowerCase();
        return haystack.contains(_query);
      });
    }

    final sorted = visible.toList(growable: false);
    switch (_sort) {
      case _StatementSort.newest:
        sorted.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      case _StatementSort.oldest:
        sorted.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      case _StatementSort.amountHigh:
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
      case _StatementSort.amountLow:
        sorted.sort((a, b) => a.amount.compareTo(b.amount));
    }

    return sorted;
  }

  List<SavingsStatementEntry> _filterSavingsEntries(
    List<SavingsStatementEntry> entries,
  ) {
    Iterable<SavingsStatementEntry> visible = entries;

    visible = visible.where((entry) => _matchesSelectedRange(entry.createdAt));

    switch (_savingsFilter) {
      case _SavingsFilter.all:
        break;
      case _SavingsFilter.confirmed:
        visible = visible.where((entry) => entry.status == 'confirmed');
      case _SavingsFilter.pending:
        visible = visible.where((entry) => entry.status == 'pending');
      case _SavingsFilter.failed:
        visible = visible.where((entry) => entry.status == 'failed');
    }

    if (_query.isNotEmpty) {
      visible = visible.where((entry) {
        final haystack = <String>[
          entry.groupName,
          entry.reference ?? '',
          entry.status,
        ].join(' ').toLowerCase();
        return haystack.contains(_query);
      });
    }

    final sorted = visible.toList(growable: false);
    switch (_sort) {
      case _StatementSort.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _StatementSort.oldest:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _StatementSort.amountHigh:
        sorted.sort((a, b) => b.amount.compareTo(a.amount));
      case _StatementSort.amountLow:
        sorted.sort((a, b) => a.amount.compareTo(b.amount));
    }

    return sorted;
  }

  Future<void> _exportStatement(
    BuildContext context, {
    required MomoStatementBundle bundle,
    required String userName,
    required String officialPhone,
  }) async {
    final format = await _showExportFormatSheet(context);
    if (!context.mounted || format == null) {
      return;
    }

    final timestamp = DateTime.now();
    final box = context.findRenderObject() as RenderBox?;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final metadata = StatementExportMetadata(
      statementTitle: _activeTab == _StatementTab.wallet
          ? 'Wallet Statement'
          : 'Group Savings Statement',
      fileStem: _activeTab == _StatementTab.wallet
          ? 'cool_wallet_statement'
          : 'cool_group_savings_statement',
      userName: userName,
      officialPhone: officialPhone,
      generatedAt: timestamp,
      periodLabel: _periodLabel,
      filterLabel: _activeTab == _StatementTab.wallet
          ? _walletFilterLabel(_walletFilter)
          : _savingsFilterLabel(_savingsFilter),
      sortLabel: _sortLabel(_sort),
      searchQuery: _searchController.text.trim(),
    );

    try {
      final export = _activeTab == _StatementTab.wallet
          ? await _exportService.buildWalletExport(
              format: format,
              entries: _filterWalletEntries(bundle.walletEntries),
              metadata: metadata,
            )
          : await _exportService.buildSavingsExport(
              format: format,
              entries: _filterSavingsEntries(bundle.savingsEntries),
              metadata: metadata,
            );

      await SharePlus.instance.share(
        ShareParams(
          title: 'COOL Statement Export',
          subject: 'COOL statement export',
          files: [XFile.fromData(export.bytes, mimeType: export.mimeType)],
          fileNameOverrides: [export.fileName],
          downloadFallbackEnabled: true,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not export statement: $error')),
      );
    }
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _statementRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: AppColors.bg,
              surface: AppColors.surface2,
              onSurface: AppColors.text,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (!mounted || range == null) {
      return;
    }

    setState(() => _statementRange = range);
  }

  Future<StatementExportFormat?> _showExportFormatSheet(
    BuildContext context,
  ) async {
    return showModalBottomSheet<StatementExportFormat>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export statement',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Export the currently filtered statement window as a branded file.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 16),
                _ExportOptionTile(
                  icon: Icons.picture_as_pdf_outlined,
                  title: 'PDF statement',
                  subtitle:
                      'Branded layout with logo, holder profile, and summary.',
                  onTap: () =>
                      Navigator.of(context).pop(StatementExportFormat.pdf),
                ),
                const SizedBox(height: 10),
                _ExportOptionTile(
                  icon: Icons.grid_on_rounded,
                  title: 'Excel workbook',
                  subtitle:
                      'Structured .xlsx ledger for sorting, formulas, and review.',
                  onTap: () =>
                      Navigator.of(context).pop(StatementExportFormat.excel),
                ),
                const SizedBox(height: 10),
                _ExportOptionTile(
                  icon: Icons.table_chart_outlined,
                  title: 'CSV data',
                  subtitle:
                      'Lightweight export for spreadsheet import or reconciliation.',
                  onTap: () =>
                      Navigator.of(context).pop(StatementExportFormat.csv),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _matchesSelectedRange(DateTime dateTime) {
    final range = _statementRange;
    if (range == null) {
      return true;
    }

    final start = DateUtils.dateOnly(range.start);
    final endExclusive = DateUtils.dateOnly(
      range.end,
    ).add(const Duration(days: 1));
    return !dateTime.isBefore(start) && dateTime.isBefore(endExclusive);
  }

  String get _periodLabel {
    final range = _statementRange;
    if (range == null) {
      return 'All recorded activity';
    }

    final formatter = DateFormat('dd MMM yyyy');
    return '${formatter.format(range.start)} - ${formatter.format(range.end)}';
  }
}

class _StatementHeroCard extends StatelessWidget {
  const _StatementHeroCard({
    required this.userName,
    required this.officialPhone,
    required this.activeTab,
    required this.walletEntries,
    required this.savingsEntries,
    required this.periodLabel,
  });

  final String userName;
  final String officialPhone;
  final _StatementTab activeTab;
  final List<MomoWalletEntry> walletEntries;
  final List<SavingsStatementEntry> savingsEntries;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final incomingTotal = walletEntries
        .where((entry) => entry.isCredit)
        .fold<int>(0, (sum, entry) => sum + entry.amount);
    final outgoingTotal = walletEntries
        .where((entry) => entry.isDebit)
        .fold<int>(0, (sum, entry) => sum + entry.amount);
    final confirmedSavingsTotal = savingsEntries
        .where((entry) => entry.isConfirmed)
        .fold<int>(0, (sum, entry) => sum + entry.amount);
    final pendingSavingsCount = savingsEntries
        .where((entry) => entry.status == 'pending')
        .length;

    return CoolCard(
      gradient: activeTab == _StatementTab.wallet
          ? AppColors.blueGradient
          : AppColors.purpleGradient,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border2),
                  ),
                  alignment: Alignment.center,
                  child: const CoolBrandMark(size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeTab == _StatementTab.wallet
                            ? 'Wallet Ledger'
                            : 'Group Savings Ledger',
                        style: GoogleFonts.dmSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$userName${officialPhone.isNotEmpty ? ' • $officialPhone' : ''}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: AppColors.text3,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              periodLabel,
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (activeTab == _StatementTab.wallet)
              Row(
                children: [
                  Expanded(
                    child: _StatementMetricTile(
                      label: 'Incoming',
                      value: '${_formatAmount(incomingTotal)} RWF',
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatementMetricTile(
                      label: 'Outgoing',
                      value: '${_formatAmount(outgoingTotal)} RWF',
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatementMetricTile(
                      label: 'Entries',
                      value: '${walletEntries.length}',
                      color: AppColors.blue,
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _StatementMetricTile(
                      label: 'Confirmed',
                      value: '${_formatAmount(confirmedSavingsTotal)} RWF',
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatementMetricTile(
                      label: 'Pending',
                      value: '$pendingSavingsCount',
                      color: AppColors.yellow,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatementMetricTile(
                      label: 'Entries',
                      value: '${savingsEntries.length}',
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatementMetricTile extends StatelessWidget {
  const _StatementMetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatementTabSelector extends StatelessWidget {
  const _StatementTabSelector({
    required this.activeTab,
    required this.onChanged,
  });

  final _StatementTab activeTab;
  final ValueChanged<_StatementTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SegmentChip(
            label: 'Wallet',
            icon: '📲',
            selected: activeTab == _StatementTab.wallet,
            onTap: () => onChanged(_StatementTab.wallet),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SegmentChip(
            label: 'Group Savings',
            icon: '👥',
            selected: activeTab == _StatementTab.savings,
            onTap: () => onChanged(_StatementTab.savings),
          ),
        ),
      ],
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentGlow : AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.accent : AppColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementSearchBar extends StatelessWidget {
  const _StatementSearchBar({
    required this.controller,
    required this.onChanged,
    required this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.text2),
          hintText: hintText,
          hintStyle: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}

class _StatementToolbar extends StatelessWidget {
  const _StatementToolbar({
    required this.activeTab,
    required this.sort,
    required this.onSortChanged,
    this.onExport,
  });

  final _StatementTab activeTab;
  final _StatementSort sort;
  final ValueChanged<_StatementSort> onSortChanged;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border2),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.swap_vert_rounded,
                  color: AppColors.text2,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sort: ${_sortLabel(sort)}',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                PopupMenuButton<_StatementSort>(
                  initialValue: sort,
                  onSelected: onSortChanged,
                  color: AppColors.surface2,
                  itemBuilder: (_) => _StatementSort.values
                      .map(
                        (value) => PopupMenuItem<_StatementSort>(
                          value: value,
                          child: Text(
                            _sortLabel(value),
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: AppColors.text2,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onExport,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: onExport == null
                    ? AppColors.surface3
                    : AppColors.accentGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: onExport == null ? AppColors.border : AppColors.accent,
                ),
              ),
              child: Icon(
                activeTab == _StatementTab.wallet
                    ? Icons.file_download_outlined
                    : Icons.table_view_rounded,
                color: onExport == null ? AppColors.text3 : AppColors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatementRangeBar extends StatelessWidget {
  const _StatementRangeBar({
    required this.label,
    required this.hasCustomRange,
    required this.onPickRange,
    this.onClearRange,
  });

  final String label;
  final bool hasCustomRange;
  final VoidCallback onPickRange;
  final VoidCallback? onClearRange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPickRange,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasCustomRange
                        ? AppColors.accent
                        : AppColors.border2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range_rounded,
                      size: 18,
                      color: hasCustomRange
                          ? AppColors.accent
                          : AppColors.text2,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onClearRange != null) ...[
          const SizedBox(width: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onClearRange,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                width: 54,
                height: 50,
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border2),
                ),
                child: const Icon(Icons.close_rounded, color: AppColors.text2),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WalletFilterChips extends StatelessWidget {
  const _WalletFilterChips({required this.value, required this.onChanged});

  final _WalletFilter value;
  final ValueChanged<_WalletFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in _WalletFilter.values)
          _MiniFilterChip(
            label: _walletFilterLabel(filter),
            selected: value == filter,
            onTap: () => onChanged(filter),
          ),
      ],
    );
  }
}

class _SavingsFilterChips extends StatelessWidget {
  const _SavingsFilterChips({required this.value, required this.onChanged});

  final _SavingsFilter value;
  final ValueChanged<_SavingsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in _SavingsFilter.values)
          _MiniFilterChip(
            label: _savingsFilterLabel(filter),
            selected: value == filter,
            onTap: () => onChanged(filter),
          ),
      ],
    );
  }
}

class _ExportOptionTile extends StatelessWidget {
  const _ExportOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border2),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border2),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniFilterChip extends StatelessWidget {
  const _MiniFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.blueGlow : AppColors.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.blue : AppColors.border2,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.blue : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletStatementList extends StatelessWidget {
  const _WalletStatementList({required this.entries});

  final List<MomoWalletEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyStatementCard(
        emoji: '📭',
        title: 'No wallet entries match the current filters',
        message:
            'Posted mobile-money ledger entries appear here once MOMO parsing and reconciliation complete.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          _WalletEntryCard(entry: entries[i]),
          if (i != entries.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _SavingsStatementList extends StatelessWidget {
  const _SavingsStatementList({required this.entries});

  final List<SavingsStatementEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyStatementCard(
        emoji: '👥',
        title: 'No savings entries match the current filters',
        message:
            'Your confirmed and pending savings-group contributions will appear here across all groups.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          _SavingsEntryCard(entry: entries[i]),
          if (i != entries.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _WalletEntryCard extends StatelessWidget {
  const _WalletEntryCard({required this.entry});

  final MomoWalletEntry entry;

  @override
  Widget build(BuildContext context) {
    final iconBg = entry.isCredit ? AppColors.accentGlow : AppColors.blueGlow;
    final iconColor = entry.isCredit ? AppColors.accent : AppColors.blue;
    final amountColor = entry.isCredit ? AppColors.accent : AppColors.orange;
    final amountPrefix = entry.isCredit ? '+' : '-';

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    entry.isCredit
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.label,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.counterpartyName ??
                            _titleizeLedgerSide(entry.entryType),
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$amountPrefix${_formatAmount(entry.amount)} ${entry.currency}',
                      style: GoogleFonts.dmMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('d MMM y · HH:mm').format(entry.occurredAt),
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _LedgerPill(
                    label: _categoryLabel(entry.txCategory),
                    color: _categoryColor(entry.cashflowBucket),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LedgerPill(
                    label: _statusLabel(entry.ledgerStatus),
                    color: _statusColor(entry.ledgerStatus),
                  ),
                ),
              ],
            ),
            if ((entry.reference?.isNotEmpty ?? false) ||
                (entry.description?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.reference?.isNotEmpty ?? false)
                      Text(
                        'Ref: ${entry.reference}',
                        style: GoogleFonts.dmMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text2,
                        ),
                      ),
                    if ((entry.reference?.isNotEmpty ?? false) &&
                        (entry.description?.isNotEmpty ?? false))
                      const SizedBox(height: 6),
                    if (entry.description?.isNotEmpty ?? false)
                      Text(
                        entry.description!,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text2,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavingsEntryCard extends StatelessWidget {
  const _SavingsEntryCard({required this.entry});

  final SavingsStatementEntry entry;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accentGlow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Text('👥', style: TextStyle(fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.groupName,
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('d MMM y · HH:mm').format(entry.createdAt),
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '+${_formatAmount(entry.amount)} RWF',
                  style: GoogleFonts.dmMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _LedgerPill(
                    label: _statusLabel(entry.status),
                    color: _statusColor(entry.status),
                  ),
                ),
                if (entry.reference?.isNotEmpty ?? false) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LedgerPill(
                      label: 'MOMO ref available',
                      color: AppColors.blue,
                    ),
                  ),
                ],
              ],
            ),
            if (entry.reference?.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Ref: ${entry.reference}',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LedgerPill extends StatelessWidget {
  const _LedgerPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyStatementCard extends StatelessWidget {
  const _EmptyStatementCard({
    required this.emoji,
    required this.title,
    required this.message,
  });

  final String emoji;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementLoadingState extends StatelessWidget {
  const _StatementLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _LoadingCard(),
        SizedBox(height: 12),
        _LoadingCard(),
        SizedBox(height: 12),
        _LoadingCard(),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final MomoPaymentSyncState state;

  @override
  Widget build(BuildContext context) {
    final statusText = !state.isSupportedPlatform
        ? 'Unsupported'
        : !state.isPolicyEnabled
        ? 'Disabled'
        : switch (state.permissionStatus) {
            MomoSmsPermissionStatus.supportedGranted => 'Granted',
            MomoSmsPermissionStatus.supportedDenied => 'Denied',
            MomoSmsPermissionStatus.supportedPermanentlyDenied => 'Blocked',
            MomoSmsPermissionStatus.unsupported => 'Unsupported',
          };

    final statusBadge = !state.isSupportedPlatform
        ? const StatusBadge(
            label: 'Android only',
            bgColor: AppColors.surface3,
            textColor: AppColors.text2,
          )
        : !state.isPolicyEnabled
        ? const StatusBadge(
            label: 'Disabled',
            bgColor: AppColors.surface3,
            textColor: AppColors.text2,
          )
        : switch (state.permissionStatus) {
            MomoSmsPermissionStatus.supportedGranted => const StatusBadge(
              label: 'Active',
              bgColor: AppColors.accentGlow,
              textColor: AppColors.accent,
              emoji: '●',
            ),
            MomoSmsPermissionStatus.supportedDenied => const StatusBadge(
              label: 'Permission denied',
              bgColor: AppColors.surface3,
              textColor: AppColors.text2,
              emoji: '⚠️',
            ),
            MomoSmsPermissionStatus.supportedPermanentlyDenied =>
              const StatusBadge(
                label: 'Permission blocked',
                bgColor: Color(0x26FF4D6A),
                textColor: AppColors.red,
                emoji: '⛔',
              ),
            MomoSmsPermissionStatus.unsupported => const StatusBadge(
              label: 'Android only',
              bgColor: AppColors.surface3,
              textColor: AppColors.text2,
            ),
          };

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                        'SMS verification status',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Statements below use the posted backend ledger. Android SMS verification remains an optional source that helps recover fresh MOMO transactions.',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text2,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                statusBadge,
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MetricBox(
                    label: 'Listener',
                    value: state.isListening ? 'ON' : 'OFF',
                    valueColor: state.isListening
                        ? AppColors.accent
                        : AppColors.text2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricBox(
                    label: 'Permission',
                    value: statusText,
                    valueColor: switch (state.permissionStatus) {
                      MomoSmsPermissionStatus.supportedGranted =>
                        AppColors.accent,
                      MomoSmsPermissionStatus.supportedDenied =>
                        AppColors.orange,
                      MomoSmsPermissionStatus.supportedPermanentlyDenied =>
                        AppColors.red,
                      MomoSmsPermissionStatus.unsupported => AppColors.text2,
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricBox(
                    label: 'Recovered',
                    value: '${state.recoveredTransactions}',
                    valueColor: AppColors.blue,
                  ),
                ),
              ],
            ),
            if (state.lastReference != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Text(
                  'Last confirmed reference: ${state.lastReference}',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 14),
              Text(
                state.error!,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.orange,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends ConsumerWidget {
  const _ActionCard({required this.state});

  final MomoPaymentSyncState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(momoPaymentSyncProvider.notifier);

    if (!state.isSupportedPlatform || !state.isPolicyEnabled) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            !state.isSupportedPlatform
                ? 'Incoming SMS auto-read is not available on this platform.'
                : 'SMS auto-read is not available in this build.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
            ),
          ),
        ),
      );
    }

    if (!state.hasUserConsent) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enable Android SMS verification',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Grant explicit consent before Cool starts verifying incoming M-Money payment confirmations from approved sender IDs.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: AppColors.text2,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              CoolButton(
                label: 'Enable verification',
                onTap: () {
                  unawaited(notifier.enableSmsSync());
                },
              ),
            ],
          ),
        ),
      );
    }

    switch (state.permissionStatus) {
      case MomoSmsPermissionStatus.supportedDenied:
        return CoolCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SMS permission required',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Grant Android SMS permission so Cool can verify M-Money contributions and subscriptions automatically. Only approved sender IDs are processed.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                CoolButton(
                  label: 'Grant SMS access',
                  onTap: () {
                    unawaited(notifier.retrySmsSetup());
                  },
                ),
              ],
            ),
          ),
        );
      case MomoSmsPermissionStatus.supportedPermanentlyDenied:
        return CoolCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SMS permission blocked',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Open Android settings and enable SMS permission for Cool to restore automatic M-Money payment verification.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                CoolButton(
                  label: 'Open settings',
                  onTap: () {
                    unawaited(notifier.openSmsSettings());
                  },
                ),
              ],
            ),
          ),
        );
      case MomoSmsPermissionStatus.supportedGranted:
      case MomoSmsPermissionStatus.unsupported:
        return CoolCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.isListening
                        ? 'SMS recovery is active on this device. Fresh confirmations should move into the backend statement ledger automatically.'
                        : 'SMS permission is granted. Use retry if you want to restart the listener.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 132,
                  child: CoolButton(
                    label: 'Retry',
                    variant: CoolButtonVariant.secondary,
                    onTap: () {
                      unawaited(notifier.retrySmsSetup());
                    },
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.dmMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry});

  final MomoSmsHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final tx = entry.transaction;
    final statusBadge = switch (entry.status) {
      MomoSmsHistoryStatus.detected => const StatusBadge(
        label: 'Detected',
        bgColor: AppColors.blueGlow,
        textColor: AppColors.blue,
        emoji: '📥',
      ),
      MomoSmsHistoryStatus.processing => const StatusBadge(
        label: 'Processing',
        bgColor: AppColors.blueGlow,
        textColor: AppColors.blue,
        emoji: '⏳',
      ),
      MomoSmsHistoryStatus.confirmed => const StatusBadge(
        label: 'Confirmed',
        bgColor: AppColors.accentGlow,
        textColor: AppColors.accent,
        emoji: '✅',
      ),
      MomoSmsHistoryStatus.reviewRequired => const StatusBadge(
        label: 'Review',
        bgColor: Color(0x26FFD166),
        textColor: AppColors.yellow,
        emoji: '📝',
      ),
      MomoSmsHistoryStatus.unmatched => const StatusBadge(
        label: 'Unmatched',
        bgColor: Color(0x26FF6B35),
        textColor: AppColors.orange,
        emoji: '⚠️',
      ),
    };

    final typeLabel = switch (tx.type) {
      MomoTxType.received => 'Received',
      MomoTxType.sent => 'Sent',
      MomoTxType.payment => 'Payment',
    };

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        '$typeLabel · ${tx.provider} ${tx.country}',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEE d MMM / hh:mm a').format(tx.receivedAt),
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                statusBadge,
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _DetailColumn(
                    label: 'Amount',
                    value: '${tx.amountRwf} RWF',
                    mono: true,
                    valueColor: AppColors.accent,
                  ),
                ),
                Expanded(
                  child: _DetailColumn(
                    label: 'Tx ID',
                    value: tx.transactionId ?? 'Unavailable',
                    mono: true,
                  ),
                ),
              ],
            ),
            if (entry.matchedReference != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent),
                ),
                child: Text(
                  'Matched reference: ${entry.matchedReference}',
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              tx.rawMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailColumn extends StatelessWidget {
  const _DetailColumn({
    required this.label,
    required this.value,
    this.mono = false,
    this.valueColor = AppColors.text,
  });

  final String label;
  final String value;
  final bool mono;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono
              ? GoogleFonts.dmMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                )
              : GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
        ),
      ],
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard();

  @override
  Widget build(BuildContext context) {
    return const _EmptyStatementCard(
      emoji: '📭',
      title: 'No M-Money verification activity yet',
      message:
          'When Cool detects approved M-Money payment confirmations on Android, they appear here with processing, confirmation, or review status.',
    );
  }
}

class _HistoryLoadingList extends StatelessWidget {
  const _HistoryLoadingList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _LoadingCard(),
        SizedBox(height: 12),
        _LoadingCard(),
        SizedBox(height: 12),
        _LoadingCard(),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: SizedBox(
        height: 132,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 2.2,
          ),
        ),
      ),
    );
  }
}

class _HistoryErrorCard extends StatelessWidget {
  const _HistoryErrorCard({
    required this.message,
    required this.onRetry,
    this.title = 'Unable to load SMS history',
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 32)),
            const SizedBox(height: 10),
            Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            CoolButton(
              label: 'Retry',
              variant: CoolButtonVariant.secondary,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

String _walletFilterLabel(_WalletFilter value) {
  switch (value) {
    case _WalletFilter.all:
      return 'All';
    case _WalletFilter.incoming:
      return 'Incoming';
    case _WalletFilter.outgoing:
      return 'Outgoing';
    case _WalletFilter.savings:
      return 'Savings';
    case _WalletFilter.expense:
      return 'Expenses';
  }
}

String _savingsFilterLabel(_SavingsFilter value) {
  switch (value) {
    case _SavingsFilter.all:
      return 'All';
    case _SavingsFilter.confirmed:
      return 'Confirmed';
    case _SavingsFilter.pending:
      return 'Pending';
    case _SavingsFilter.failed:
      return 'Failed';
  }
}

String _sortLabel(_StatementSort value) {
  switch (value) {
    case _StatementSort.newest:
      return 'Newest first';
    case _StatementSort.oldest:
      return 'Oldest first';
    case _StatementSort.amountHigh:
      return 'Amount high-low';
    case _StatementSort.amountLow:
      return 'Amount low-high';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'posted':
    case 'confirmed':
      return 'Confirmed';
    case 'pending':
    case 'draft':
      return 'Pending';
    case 'reversed':
    case 'failed':
      return 'Failed';
    default:
      return status.replaceAll('_', ' ');
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'posted':
    case 'confirmed':
      return AppColors.accent;
    case 'pending':
    case 'draft':
      return AppColors.yellow;
    case 'reversed':
    case 'failed':
      return AppColors.red;
    default:
      return AppColors.text2;
  }
}

String _categoryLabel(String category) {
  final normalized = category.trim();
  if (normalized.isEmpty) {
    return 'Uncategorized';
  }

  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

Color _categoryColor(String cashflowBucket) {
  switch (cashflowBucket) {
    case 'income':
      return AppColors.accent;
    case 'expense':
      return AppColors.orange;
    case 'savings':
      return AppColors.blue;
    case 'loan':
      return AppColors.yellow;
    case 'fees':
      return AppColors.red;
    default:
      return AppColors.text2;
  }
}

String _formatAmount(int amount) {
  final formatter = NumberFormat('#,###');
  return formatter.format(amount);
}

String _titleizeLedgerSide(String entryType) {
  return entryType == 'credit'
      ? 'Incoming wallet entry'
      : 'Outgoing wallet entry';
}
