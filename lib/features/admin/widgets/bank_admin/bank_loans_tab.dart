import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/cool_palette.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../providers/bank_admin_providers.dart';
import 'bank_admin_helpers.dart';
import 'package:cool_app/core/l10n/l10n.dart';

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

  static const _statuses = [
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
    final palette = context.coolPalette;
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
                label: Text(bankTitle(s)),
                selected: active,
                onSelected: (_) => onStatusFilterChanged(s),
                backgroundColor: palette.surface2,
                selectedColor: palette.accent.withValues(alpha: 0.15),
                labelStyle: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? palette.accent : palette.text2,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: loansAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(context.l10n.genericErrorText(e.toString()))),
            data: (loans) {
              final filtered = statusFilter == 'all'
                  ? loans
                  : loans
                        .where(
                          (l) =>
                              (l['status']?.toString() ?? '') ==
                              statusFilter,
                        )
                        .toList();
              if (filtered.isEmpty) {
                return const CoolEmptyView(
                  message: 'No loans match filter',
                  compact: true,
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final loan = filtered[index];
                  final amount =
                      (loan['amount'] as num?)?.toDouble() ?? 0;
                  final repaid =
                      (loan['repaid_amount'] as num?)?.toDouble() ??
                          0;
                  final status =
                      loan['status']?.toString() ?? 'pending';
                  final memberName =
                      loan['member_name']?.toString() ?? '—';
                  final groupName =
                      loan['group_name']?.toString() ?? '—';

                  return CoolCard(
                    backgroundColor: palette.surface,
                    borderColor: palette.border,
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
                                  color: palette.text,
                                ),
                              ),
                            ),
                            BankStatusTag(
                              label: bankTitle(status),
                              backgroundColor: bankLoanStatusColor(
                                status,
                              ).withValues(alpha: 0.15),
                              foregroundColor:
                                  bankLoanStatusColor(status),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          groupName,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: palette.text3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            BankInfoPill(
                              label: 'Amount',
                              value:
                                  '${moneyFmt.format(amount)} RWF',
                            ),
                            const SizedBox(width: 8),
                            BankInfoPill(
                              label: 'Repaid',
                              value:
                                  '${moneyFmt.format(repaid)} RWF',
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
                                        .read(
                                          bankAdminRepositoryProvider,
                                        )
                                        .updateLoanStatus(
                                          loanId:
                                              loan['id'].toString(),
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
                                        .read(
                                          bankAdminRepositoryProvider,
                                        )
                                        .updateLoanStatus(
                                          loanId:
                                              loan['id'].toString(),
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
                              icon: const Icon(
                                Icons.send_rounded,
                                size: 16,
                              ),
                              onPressed: () async {
                                await ref
                                    .read(
                                      bankAdminRepositoryProvider,
                                    )
                                    .updateLoanStatus(
                                      loanId:
                                          loan['id'].toString(),
                                      status: 'disbursed',
                                    );
                                ref.invalidate(
                                  bankLoansProvider(partnerId),
                                );
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