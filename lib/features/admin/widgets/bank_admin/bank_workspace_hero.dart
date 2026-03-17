import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../models/bank_admin_models.dart';
import '../../../../core/l10n/l10n.dart';

class BankWorkspaceHero extends StatelessWidget {
  const BankWorkspaceHero({
    required this.partnerName,
    required this.snapshot,
    required this.analyticsAsync,
    super.key,
  });

  final String partnerName;
  final BankAdminWorkspaceSnapshot snapshot;
  final AsyncValue<Map<String, dynamic>> analyticsAsync;

  @override
  Widget build(BuildContext context) {
    final moneyFormat = NumberFormat.decimalPattern('en_US');
    return CoolCard(
      backgroundColor: AppColors.surface,
      borderColor: AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            partnerName,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Custodian workspace for group savings and loans.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricChip(
                label: context.l10n.groups2,
                value: snapshot.groups.totalCount.toString(),
              ),
              _MetricChip(
                label: context.l10n.members,
                value: snapshot.members.totalCount.toString(),
              ),
              _MetricChip(
                label: context.l10n.contributions1,
                value: snapshot.contributions.totalCount.toString(),
              ),
              _MetricChip(
                label: context.l10n.manualReview,
                value: snapshot.allocations.totalCount.toString(),
              ),
            ],
          ),
          analyticsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (data) {
              if (data.isEmpty) return const SizedBox.shrink();
              final totalAum = (data['total_aum'] as num?)?.toDouble() ?? 0;
              final loansOutstanding =
                  (data['loans_outstanding'] as num?)?.toDouble() ?? 0;
              final activeBasketsCount =
                  (data['active_baskets_count'] as num?)?.toInt() ?? 0;
              final activeLoansCount =
                  (data['active_loans_count'] as num?)?.toInt() ?? 0;
              if (totalAum == 0 &&
                  loansOutstanding == 0 &&
                  activeBasketsCount == 0) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'Financial Summary',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricChip(
                        label: context.l10n.aum,
                        value: '${moneyFormat.format(totalAum)} RWF',
                      ),
                      _MetricChip(
                        label: context.l10n.loansOut,
                        value:
                            '${moneyFormat.format(loansOutstanding)} RWF',
                      ),
                      _MetricChip(
                        label: 'active loans',
                        value: activeLoansCount.toString(),
                      ),
                      _MetricChip(
                        label: 'active baskets',
                        value: activeBasketsCount.toString(),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$value $label',
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      ),
    );
  }
}