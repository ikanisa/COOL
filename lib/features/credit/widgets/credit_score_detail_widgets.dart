import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../models/credit_dashboard.dart';

class ImprovementItem {
  const ImprovementItem(this.text, this.completed);

  final String text;
  final bool completed;
}

class ReasonInsight {
  const ReasonInsight({
    required this.code,
    required this.title,
    required this.detail,
    required this.action,
    required this.icon,
    required this.color,
  });

  final String code;
  final String title;
  final String detail;
  final String action;
  final IconData icon;
  final Color color;
}

/// Yellow info banner at the top of the credit screen.
class CreditInfoBanner extends StatelessWidget {
  const CreditInfoBanner({
    required this.icon,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final insets = context.coolInsets;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: insets.symmetric(
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x2 + 2,
      ),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs - 2)),
        border: Border.all(color: colors.warning.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.warning),
          SizedBox(width: CoolSpace.x2),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Next steps" improvement checklist card.
class HowToImproveCard extends StatelessWidget {
  const HowToImproveCard({required this.dashboard, super.key});

  final CreditDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    final items = _buildItems(dashboard, colors);

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next steps',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: CoolSpace.x3),
          ...items.map((item) {
            return Padding(
              padding: insets.only(bottom: CoolSpace.x2 + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.completed
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: item.completed
                        ? colors.success
                        : colors.tertiaryText,
                  ),
                  SizedBox(width: CoolSpace.x2 + 2),
                  Expanded(
                    child: Text(
                      item.text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: item.completed
                            ? colors.primaryText
                            : colors.secondaryText,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  List<ImprovementItem> _buildItems(
    CreditDashboard? data,
    CoolSemanticColors colors,
  ) {
    if (data == null) {
      return const [ImprovementItem('Sign in to view your report', false)];
    }

    if (!data.hasReport) {
      return [
        ImprovementItem(
          'Keep mobile-money activity flowing',
          data.statementCount > 0,
        ),
        ImprovementItem(
          'Stay active in savings groups',
          data.groupContributionCount > 0,
        ),
        ImprovementItem(
          'Build 2+ active months of history',
          data.activeMonthCount >= 2,
        ),
      ];
    }

    final recommendations = reasonInsights(data, colors)
        .map((item) => item.action)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (recommendations.isEmpty) {
      return const [
        ImprovementItem('Maintain your current savings consistency', true),
        ImprovementItem('Keep your verified M-Money history active', true),
        ImprovementItem('Stay active in your savings groups', true),
      ];
    }

    return recommendations
        .map(
          (item) => ImprovementItem(
            item,
            item ==
                'Maintain current wallet, savings, and profile verification behaviour.',
          ),
        )
        .toList(growable: false);
  }
}

/// CTA card to open the readiness screen.
class ApplicationReadinessEntryCard extends StatelessWidget {
  const ApplicationReadinessEntryCard({required this.dashboard, super.key});

  final CreditDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final title = dashboard?.hasReport == true
        ? 'Ready for a formal handoff'
        : 'Build readiness first';
    final detail = dashboard?.hasReport == true
        ? 'Prepare for your next finance conversation.'
        : 'See what still needs to be completed.';

    return CoolCard(
      backgroundColor: colors.financialSurface,
      borderColor: colors.info.withValues(alpha: 0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: CoolSpace.x2),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          SizedBox(height: CoolSpace.x3 + 2),
          CoolButton(
            label: context.l10n.openReadiness,
            icon: Icons.assignment_turned_in_outlined,
            onTap: () => context.push(AppRoutes.creditReadiness),
          ),
        ],
      ),
    );
  }
}

/// Score explanation card with meta chips, stats, and reason insights.
class ScoreExplanationCard extends StatelessWidget {
  const ScoreExplanationCard({required this.dashboard, super.key});

  final CreditDashboard? dashboard;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    final data = dashboard;
    if (data == null) {
      return CoolCard(
        child: Padding(
          padding: insets.all(CoolSpace.x5 - 2),
          child: Text(
            'Sign in to view score details.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    if (!data.hasReport) {
      return CoolCard(
        child: Padding(
          padding: insets.all(CoolSpace.x5 - 2),
          child: Text(
            'Details appear after your credit report is ready.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    final insights = reasonInsights(data, colors);

    return CoolCard(
      child: Padding(
        padding: insets.all(CoolSpace.x5 - 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: CoolSpace.x2,
              runSpacing: CoolSpace.x2,
              children: [
                _ReportMetaChip(
                  label: context.l10n.window,
                  value: _scoringWindowLabel(data),
                  icon: Icons.calendar_month_rounded,
                ),
                _ReportMetaChip(
                  label: context.l10n.kyc,
                  value: _kycStatusLabel(data.kycStatus),
                  icon: Icons.verified_user_outlined,
                ),
                if ((data.scoreVersion?.trim().isNotEmpty ?? false))
                  _ReportMetaChip(
                    label: context.l10n.engine,
                    value: data.scoreVersion!,
                    icon: Icons.tune_rounded,
                  ),
              ],
            ),
            SizedBox(height: CoolSpace.x3 + 2),
            Wrap(
              spacing: CoolSpace.x2,
              runSpacing: CoolSpace.x2,
              children: [
                _SnapshotStatTile(
                  label: context.l10n.walletIn,
                  value:
                      '${_formatCurrency(data.creditTotal)} RWF\n${data.creditEntryCount} credits',
                  color: colors.success,
                ),
                _SnapshotStatTile(
                  label: context.l10n.walletOut,
                  value:
                      '${_formatCurrency(data.debitTotal)} RWF\n${data.debitEntryCount} debits',
                  color: colors.warning,
                ),
                _SnapshotStatTile(
                  label: context.l10n.savings,
                  value:
                      '${_formatCurrency(data.groupTotal)} RWF\n${data.groupContributionCount} contributions',
                  color: colors.info,
                ),
                _SnapshotStatTile(
                  label: context.l10n.averageSave,
                  value:
                      '${_formatCurrency(data.averageGroupContribution)} RWF\n${data.activeMonthCount} months',
                  color: colors.accent,
                ),
              ],
            ),
            SizedBox(height: CoolSpace.x4),
            ...insights.map(
              (item) => Padding(
                padding: insets.only(bottom: CoolSpace.x2 + 2),
                child: _ReasonInsightTile(item: item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading state.
class CreditScoreLoadingState extends StatelessWidget {
  const CreditScoreLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: context.coolInsets.fromLTRB(
        CoolSpace.x6,
        CoolSpace.x2,
        CoolSpace.x6,
        CoolLayout.rootBottomClearance,
      ),
      child: const Column(
        children: [
          CoolSkeleton.card(),
          SizedBox(height: CoolSpace.x5 - 2),
          CoolSkeleton.card(),
          SizedBox(height: CoolSpace.x5 - 2),
          CoolSkeleton.card(),
        ],
      ),
    );
  }
}

/// Error state.
class CreditScoreErrorState extends StatelessWidget {
  const CreditScoreErrorState({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: context.coolInsets.symmetric(horizontal: CoolSpace.x6),
      child: CoolCard(child: CoolErrorView(message: error, compact: true)),
    );
  }
}

class _ReportMetaChip extends StatelessWidget {
  const _ReportMetaChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final insets = context.coolInsets;
    final theme = Theme.of(context);
    return Container(
      padding: insets.symmetric(
        horizontal: CoolSpace.x3,
        vertical: CoolSpace.x2 + 2,
      ),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.secondaryText),
          SizedBox(width: CoolSpace.x2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.tertiaryText,
                ),
              ),
              SizedBox(height: CoolSpace.x1 / 2),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.primaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotStatTile extends StatelessWidget {
  const _SnapshotStatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final insets = context.coolInsets;
    final theme = Theme.of(context);
    return SizedBox(
      width: 152,
      child: Container(
        padding: insets.all(CoolSpace.x3 + 2),
        decoration: BoxDecoration(
          color: colors.financialSurface,
          borderRadius: const BorderRadius.all(
            Radius.circular(CoolRadii.sm - 2),
          ),
          border: Border.all(color: colors.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.tertiaryText,
              ),
            ),
            SizedBox(height: CoolSpace.x2),
            Text(
              value,
              style: context.coolText.mono(
                theme.textTheme.labelMedium,
                color: color,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonInsightTile extends StatelessWidget {
  const _ReasonInsightTile({required this.item});

  final ReasonInsight item;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final insets = context.coolInsets;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: insets.all(CoolSpace.x3 + 2),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm - 2)),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.xs - 2),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          SizedBox(width: CoolSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: CoolSpace.x1 + 1),
                Text(
                  item.detail,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.secondaryText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCurrency(int amount) {
  return NumberFormat.decimalPattern('en_US').format(amount);
}

String _scoringWindowLabel(CreditDashboard dashboard) {
  final start = dashboard.periodStart?.toLocal();
  final end = dashboard.periodEnd?.toLocal();
  if (start == null || end == null) return 'Latest available window';
  final formatter = DateFormat('d MMM yyyy');
  return '${formatter.format(start)} - ${formatter.format(end)}';
}

String _kycStatusLabel(String? rawStatus) {
  switch (rawStatus) {
    case 'verified':
      return 'Verified';
    case 'pending_review':
      return 'Pending review';
    case 'rejected':
      return 'Rejected';
    default:
      return 'Unverified';
  }
}

List<ReasonInsight> reasonInsights(
  CreditDashboard dashboard,
  CoolSemanticColors colors,
) {
  if (!dashboard.hasReport) return const <ReasonInsight>[];

  final codes = dashboard.reasonCodes.isEmpty
      ? const <String>['healthy_verified_history']
      : dashboard.reasonCodes.toSet().toList(growable: false);
  return codes
      .map((code) => _reasonInsightFor(code, dashboard, colors))
      .toList(growable: false);
}

ReasonInsight _reasonInsightFor(
  String code,
  CreditDashboard dashboard,
  CoolSemanticColors colors,
) {
  switch (code) {
    case 'wallet_activity_low':
      return ReasonInsight(
        code: code,
        title: 'Wallet history is still light',
        detail:
            'Only ${dashboard.statementCount} posted wallet entries were counted in this scoring window. More verified M-Money activity makes the score more dependable.',
        action:
            'Keep using posted M-Money transactions consistently across the next two months.',
        icon: Icons.account_balance_wallet_outlined,
        color: colors.warning,
      );
    case 'income_history_thin':
      return ReasonInsight(
        code: code,
        title: 'Incoming cashflow needs more depth',
        detail:
            '${dashboard.creditEntryCount} incoming wallet entries were detected. Regular incoming transfers over multiple months improve cashflow stability.',
        action:
            'Encourage regular incoming transfers or income deposits into the wallet.',
        icon: Icons.south_west_rounded,
        color: colors.info,
      );
    case 'savings_pattern_thin':
      return ReasonInsight(
        code: code,
        title: 'Savings pattern is not consistent yet',
        detail:
            'Confirmed savings total is ${_formatCurrency(dashboard.groupTotal)} RWF with an average contribution of ${_formatCurrency(dashboard.averageGroupContribution)} RWF.',
        action:
            'Build a steadier savings pattern with repeated confirmed contributions.',
        icon: Icons.savings_outlined,
        color: colors.accent,
      );
    case 'group_savings_missing':
      return ReasonInsight(
        code: code,
        title: 'No confirmed group savings found',
        detail:
            'The model did not find confirmed group-savings contributions inside the scoring window, so that reliability factor stayed limited.',
        action:
            'Start confirmed group savings contributions to unlock this factor.',
        icon: Icons.groups_2_outlined,
        color: colors.warning,
      );
    case 'group_activity_low':
      return ReasonInsight(
        code: code,
        title: 'Group contribution activity is low',
        detail:
            '${dashboard.groupContributionCount} confirmed contributions were counted. More months with group contributions strengthen group reliability.',
        action:
            'Increase the number of months with confirmed group contributions.',
        icon: Icons.groups_outlined,
        color: colors.info,
      );
    case 'profile_verification_needed':
      return ReasonInsight(
        code: code,
        title: 'Profile verification is holding the score back',
        detail:
            'Official identity signals are not fully complete yet. Current KYC status is ${_kycStatusLabel(dashboard.kycStatus).toLowerCase()}.',
        action: 'Complete official-name, phone, and KYC verification.',
        icon: Icons.badge_outlined,
        color: colors.danger,
      );
    case 'healthy_verified_history':
    default:
      return ReasonInsight(
        code: code,
        title: 'Verified behaviour looks healthy',
        detail:
            'Posted wallet activity, confirmed savings behaviour, and profile signals are all contributing positively in the current scoring window.',
        action:
            'Maintain current wallet, savings, and profile verification behaviour.',
        icon: Icons.verified_rounded,
        color: colors.success,
      );
  }
}
