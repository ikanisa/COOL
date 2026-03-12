import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/momo_statement.dart';
import '../providers/momo_statement_providers.dart';

enum _StatementWindow { all, last30, last90 }

class MomoStatementsScreen extends ConsumerStatefulWidget {
  const MomoStatementsScreen({super.key});

  @override
  ConsumerState<MomoStatementsScreen> createState() =>
      _MomoStatementsScreenState();
}

class _MomoStatementsScreenState extends ConsumerState<MomoStatementsScreen> {
  static final NumberFormat _moneyFormat = NumberFormat.decimalPattern('en_US');
  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd MMM yyyy, HH:mm');

  _StatementWindow _window = _StatementWindow.last90;

  MomoStatementQuery get _query {
    final now = DateTime.now();
    return switch (_window) {
      _StatementWindow.all => const MomoStatementQuery(),
      _StatementWindow.last30 => MomoStatementQuery(
        startDate: now.subtract(const Duration(days: 30)),
      ),
      _StatementWindow.last90 => MomoStatementQuery(
        startDate: now.subtract(const Duration(days: 90)),
      ),
    };
  }

  void _refresh() {
    ref.invalidate(momoStatementBundleProvider(_query));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final bundleAsync = ref.watch(momoStatementBundleProvider(_query));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          automaticallyImplyLeading: context.canPop(),
          title: Text(
            'Statements & Ledger',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh statements',
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
                tabs: const [
                  Tab(text: 'Wallet'),
                  Tab(text: 'Savings'),
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
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _StatementWindow.values
                            .map(
                              (window) => ChoiceChip(
                                label: Text(_windowLabel(window)),
                                selected: _window == window,
                                onSelected: (_) {
                                  if (_window == window) {
                                    return;
                                  }
                                  setState(() => _window = window);
                                },
                                labelStyle: GoogleFonts.dmSans(
                                  color: _window == window
                                      ? Colors.black
                                      : AppColors.text,
                                  fontWeight: FontWeight.w700,
                                ),
                                backgroundColor: AppColors.surface2,
                                selectedColor: AppColors.accent,
                                side: const BorderSide(
                                  color: AppColors.border2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _StatementOverviewCard(
                      userName: user?.fullName ?? 'COOL member',
                      officialPhone: user?.officialPhone ?? user?.phone ?? '-',
                      periodLabel: _periodLabel(),
                      walletCount: bundle.walletEntries.length,
                      savingsCount: bundle.savingsEntries.length,
                      incomingTotal: bundle.walletEntries
                          .where((entry) => entry.isCredit)
                          .fold<int>(0, (sum, entry) => sum + entry.amount),
                      outgoingTotal: bundle.walletEntries
                          .where((entry) => entry.isDebit)
                          .fold<int>(0, (sum, entry) => sum + entry.amount),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _WalletStatementTab(
                            entries: bundle.walletEntries,
                            totalCount: bundle.walletTotalCount,
                            dateFormat: _dateTimeFormat,
                          ),
                          _SavingsStatementTab(
                            entries: bundle.savingsEntries,
                            totalCount: bundle.savingsTotalCount,
                            dateFormat: _dateFormat,
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
      ),
    );
  }

  String _periodLabel() {
    final now = DateTime.now();
    return switch (_window) {
      _StatementWindow.all => 'All time',
      _StatementWindow.last30 =>
        '${_dateFormat.format(now.subtract(const Duration(days: 30)))} to ${_dateFormat.format(now)}',
      _StatementWindow.last90 =>
        '${_dateFormat.format(now.subtract(const Duration(days: 90)))} to ${_dateFormat.format(now)}',
    };
  }

  String _windowLabel(_StatementWindow window) {
    return switch (window) {
      _StatementWindow.all => 'All time',
      _StatementWindow.last30 => 'Last 30 days',
      _StatementWindow.last90 => 'Last 90 days',
    };
  }
}

class _StatementOverviewCard extends StatelessWidget {
  const _StatementOverviewCard({
    required this.userName,
    required this.officialPhone,
    required this.periodLabel,
    required this.walletCount,
    required this.savingsCount,
    required this.incomingTotal,
    required this.outgoingTotal,
  });

  final String userName;
  final String officialPhone;
  final String periodLabel;
  final int walletCount;
  final int savingsCount;
  final int incomingTotal;
  final int outgoingTotal;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.blueGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Statement overview',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$userName  •  $officialPhone',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            periodLabel,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Wallet entries', value: '$walletCount'),
              _MetricChip(label: 'Savings entries', value: '$savingsCount'),
              _MetricChip(
                label: 'Incoming',
                value:
                    _MomoStatementsScreenState._moneyFormat.format(incomingTotal),
              ),
              _MetricChip(
                label: 'Outgoing',
                value:
                    _MomoStatementsScreenState._moneyFormat.format(outgoingTotal),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletStatementTab extends StatelessWidget {
  const _WalletStatementTab({
    required this.entries,
    required this.totalCount,
    required this.dateFormat,
  });

  final List<MomoWalletEntry> entries;
  final int totalCount;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyStatementState(
        title: 'No wallet entries yet',
        message: 'Wallet activity will appear here.',
      );
    }

    return ListView.separated(
      itemCount: entries.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SectionLead(
            title: 'Wallet ledger',
            subtitle:
                'Showing ${entries.length} of $totalCount posted wallet entries.',
          );
        }

        final entry = entries[index - 1];
        return CoolCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          (entry.isCredit ? AppColors.accent : AppColors.orange)
                              .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      entry.isCredit
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      color: entry.isCredit
                          ? AppColors.accent
                          : AppColors.orange,
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
                          dateFormat.format(entry.occurredAt),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${entry.isCredit ? '+' : '-'}${_MomoStatementsScreenState._moneyFormat.format(entry.amount)} ${entry.currency}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: entry.isCredit
                          ? AppColors.accent
                          : AppColors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: entry.isCredit ? 'Incoming' : 'Outgoing',
                    color: entry.isCredit ? AppColors.accent : AppColors.orange,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.txCategory),
                    color: AppColors.blue,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.cashflowBucket),
                    color: AppColors.yellow,
                  ),
                  _StatusChip(
                    label: _humanizeToken(entry.ledgerStatus),
                    color: AppColors.purple,
                  ),
                ],
              ),
              if (entry.counterpartyName != null)
                _DetailLine(
                  label: 'Counterparty',
                  value: entry.counterpartyName!,
                ),
              if (entry.reference != null)
                _DetailLine(label: 'Reference', value: entry.reference!),
              if (entry.description != null)
                _DetailLine(label: 'Details', value: entry.description!),
            ],
          ),
        );
      },
    );
  }
}

class _SavingsStatementTab extends StatelessWidget {
  const _SavingsStatementTab({
    required this.entries,
    required this.totalCount,
    required this.dateFormat,
  });

  final List<SavingsStatementEntry> entries;
  final int totalCount;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _EmptyStatementState(
        title: 'No savings entries yet',
        message: 'Savings contributions will appear here.',
      );
    }

    return ListView.separated(
      itemCount: entries.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SectionLead(
            title: 'Savings statement',
            subtitle:
                'Showing ${entries.length} of $totalCount group contribution records.',
          );
        }

        final entry = entries[index - 1];
        return CoolCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.blueGlow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.groups_2_rounded,
                      color: AppColors.blue,
                    ),
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
                          dateFormat.format(entry.createdAt),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_MomoStatementsScreenState._moneyFormat.format(entry.amount)} RWF',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: entry.isConfirmed ? 'Confirmed' : 'Pending',
                    color: entry.isConfirmed
                        ? AppColors.accent
                        : AppColors.yellow,
                  ),
                  _StatusChip(label: 'Savings', color: AppColors.blue),
                ],
              ),
              if (entry.reference != null)
                _DetailLine(label: 'Reference', value: entry.reference!),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLead extends StatelessWidget {
  const _SectionLead({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
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
              color: AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStatementState extends StatelessWidget {
  const _EmptyStatementState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CoolCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              size: 40,
              color: AppColors.text3,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
                height: 1.5,
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(color: AppColors.text),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                color: AppColors.text3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
            height: 1.45,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

String _humanizeToken(String value) {
  return value
      .split('_')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
