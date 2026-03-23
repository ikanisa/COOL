import 'package:cool_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../providers/bank_admin_providers.dart';
import 'bank_admin_helpers.dart';

class BankLoansTab extends ConsumerWidget {
  const BankLoansTab({
    required this.partnerId,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    super.key,
  });

  final String partnerId;
  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  static const List<String> _statuses = <String>[
    'all',
    'pending',
    'approved',
    'disbursed',
    'repaying',
    'completed',
    'defaulted',
    'rejected',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
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
              final status = _statuses[index];
              final active = status == statusFilter;
              return FilterChip(
                label: Text(bankTitle(status)),
                selected: active,
                onSelected: (_) => onStatusFilterChanged(status),
                backgroundColor: colors.chipBackground,
                selectedColor: colors.chipSelectedBackground,
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  color: active ? colors.primaryText : colors.secondaryText,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: loansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(context.l10n.genericErrorText(error.toString())),
            ),
            data: (loans) {
              final filtered = statusFilter == 'all'
                  ? loans
                  : loans.where((loan) {
                      return (loan['status']?.toString() ?? '') == statusFilter;
                    }).toList();

              if (filtered.isEmpty) {
                return const CoolEmptyView(
                  message: 'No loans match filter',
                  compact: true,
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final loan = filtered[index];
                  final amount = (loan['amount'] as num?)?.toDouble() ?? 0;
                  final repaid =
                      (loan['repaid_amount'] as num?)?.toDouble() ?? 0;
                  final status = loan['status']?.toString() ?? 'pending';
                  final statusColor = bankLoanStatusColor(context, status);
                  final memberName = loan['member_name']?.toString() ?? '—';
                  final groupName = loan['group_name']?.toString() ?? '—';

                  return CoolCard(
                    backgroundColor: colors.operationalSurface,
                    useGradient: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                memberName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colors.primaryText,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            BankStatusTag(
                              label: bankTitle(status),
                              backgroundColor: statusColor.withValues(
                                alpha: 0.15,
                              ),
                              foregroundColor: statusColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          groupName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.tertiaryText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            BankInfoPill(
                              label: 'Amount',
                              value: '${moneyFmt.format(amount)} RWF',
                            ),
                            const SizedBox(width: 8),
                            BankInfoPill(
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
                                    await ref
                                        .read(bankAdminRepositoryProvider)
                                        .updateLoanStatus(
                                          loanId: loan['id'].toString(),
                                          status: 'approved',
                                        );
                                    ref.invalidate(
                                      bankLoansProvider(partnerId),
                                    );
                                  },
                                  child: Text(context.l10n.approve),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await ref
                                        .read(bankAdminRepositoryProvider)
                                        .updateLoanStatus(
                                          loanId: loan['id'].toString(),
                                          status: 'rejected',
                                        );
                                    ref.invalidate(
                                      bankLoansProvider(partnerId),
                                    );
                                  },
                                  child: Text(context.l10n.reject),
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
                                await ref
                                    .read(bankAdminRepositoryProvider)
                                    .updateLoanStatus(
                                      loanId: loan['id'].toString(),
                                      status: 'disbursed',
                                    );
                                ref.invalidate(bankLoansProvider(partnerId));
                              },
                              label: Text(context.l10n.markDisbursed),
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
