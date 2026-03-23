import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../models/bank_admin_models.dart';

EdgeInsets _bankWorkspaceHeroMetricPadding() =>
    CoolSpace.sectionPadding.copyWith(
      left: CoolSpace.x3,
      right: CoolSpace.x3,
      top: CoolSpace.x2 + 2,
      bottom: CoolSpace.x2 + 2,
    );

const BorderRadius _bankWorkspaceHeroMetricRadius = BorderRadius.all(
  Radius.circular(CoolRadii.pill),
);

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final moneyFormat = NumberFormat.decimalPattern('en_US');

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            partnerName,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Custodian workspace for group savings and loans.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
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
              if (data.isEmpty) {
                return const SizedBox.shrink();
              }

              final totalAum = (data['total_aum'] as num?)?.toDouble() ?? 0;
              final loansOutstanding =
                  (data['loans_outstanding'] as num?)?.toDouble() ?? 0;
              final activeBasketsCount =
                  (data['active_baskets_count'] as num?)?.toInt() ?? 0;
              final activeLoansCount =
                  (data['active_loans_count'] as num?)?.toInt() ?? 0;

              if (totalAum == 0 &&
                  loansOutstanding == 0 &&
                  activeBasketsCount == 0 &&
                  activeLoansCount == 0) {
                return const SizedBox.shrink();
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: CoolSpace.x4),
                  Divider(color: colors.border, height: 1),
                  const SizedBox(height: CoolSpace.x4),
                  Text(
                    'Financial Summary',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x3),
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
                        value: '${moneyFormat.format(loansOutstanding)} RWF',
                      ),
                      _MetricChip(
                        label: 'Active loans',
                        value: activeLoansCount.toString(),
                      ),
                      _MetricChip(
                        label: 'Active baskets',
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Container(
      padding: _bankWorkspaceHeroMetricPadding(),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.72),
        borderRadius: _bankWorkspaceHeroMetricRadius,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$value $label',
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
