import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../models/credit_dashboard.dart';

// ── Models ───────────────────────────────────────────────────────────────

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

// ── Widgets ──────────────────────────────────────────────────────────────

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.yellow.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.yellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.yellow,
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
    final items = _buildItems(dashboard);

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next steps',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.completed
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: item.completed ? AppColors.accent : AppColors.text3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: item.completed
                            ? AppColors.text
                            : AppColors.text2,
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

  List<ImprovementItem> _buildItems(CreditDashboard? data) {
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

    final recommendations = reasonInsights(data)
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
    final title = dashboard?.hasReport == true
        ? 'Ready for a formal handoff'
        : 'Build readiness first';
    final detail = dashboard?.hasReport == true
        ? 'Prepare for your next finance conversation.'
        : 'See what still needs to be completed.';

    return CoolCard(
      borderColor: AppColors.blue.withValues(alpha: 0.24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          CoolButton(
            label: 'Open readiness',
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
    final data = dashboard;
    if (data == null) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Sign in to view details.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    if (!data.hasReport) {
      return CoolCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Details appear after your first report.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    final insights = reasonInsights(data);

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ReportMetaChip(
                  label: 'Window',
                  value: _scoringWindowLabel(data),
                  icon: Icons.calendar_month_rounded,
                ),
                _ReportMetaChip(
                  label: 'KYC',
                  value: _kycStatusLabel(data.kycStatus),
                  icon: Icons.verified_user_outlined,
                ),
                if ((data.scoreVersion?.trim().isNotEmpty ?? false))
                  _ReportMetaChip(
                    label: 'Engine',
                    value: data.scoreVersion!,
                    icon: Icons.tune_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SnapshotStatTile(
                  label: 'Wallet In',
                  value:
                      '${_formatCurrency(data.creditTotal)} RWF\n${data.creditEntryCount} credits',
                  color: AppColors.accent,
                ),
                _SnapshotStatTile(
                  label: 'Wallet Out',
                  value:
                      '${_formatCurrency(data.debitTotal)} RWF\n${data.debitEntryCount} debits',
                  color: AppColors.orange,
                ),
                _SnapshotStatTile(
                  label: 'Savings',
                  value:
                      '${_formatCurrency(data.groupTotal)} RWF\n${data.groupContributionCount} contributions',
                  color: AppColors.blue,
                ),
                _SnapshotStatTile(
                  label: 'Average Save',
                  value:
                      '${_formatCurrency(data.averageGroupContribution)} RWF\n${data.activeMonthCount} active months',
                  color: AppColors.purple,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...insights.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
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
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 96),
      child: Column(
        children: [
          CoolSkeleton.card(),
          SizedBox(height: 18),
          CoolSkeleton.card(),
          SizedBox(height: 18),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: CoolCard(child: CoolErrorView(message: error, compact: true)),
    );
  }
}

// ── Private helpers ──────────────────────────────────────────────────────

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.text2),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
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
    return SizedBox(
      width: 152,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
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
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(item.icon, size: 18, color: item.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.detail,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
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

// ── Pure functions ───────────────────────────────────────────────────────

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

List<ReasonInsight> reasonInsights(CreditDashboard dashboard) {
  if (!dashboard.hasReport) return const <ReasonInsight>[];

  final codes = dashboard.reasonCodes.isEmpty
      ? const <String>['healthy_verified_history']
      : dashboard.reasonCodes.toSet().toList(growable: false);
  return codes
      .map((code) => _reasonInsightFor(code, dashboard))
      .toList(growable: false);
}

ReasonInsight _reasonInsightFor(String code, CreditDashboard dashboard) {
  switch (code) {
    case 'wallet_activity_low':
      return ReasonInsight(
        code: code,
        title: 'Wallet history is still thin',
        detail:
            'Only ${dashboard.statementCount} posted wallet entries were counted in this scoring window. More verified M-Money activity makes the score more dependable.',
        action:
            'Keep using posted M-Money transactions consistently across the next two months.',
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.orange,
      );
    case 'income_history_thin':
      return ReasonInsight(
        code: code,
        title: 'Incoming cashflow needs more history',
        detail:
            '${dashboard.creditEntryCount} incoming wallet entries were detected. Regular incoming transfers over multiple months improve cashflow stability.',
        action:
            'Encourage regular incoming transfers or income deposits into the wallet.',
        icon: Icons.south_west_rounded,
        color: AppColors.yellow,
      );
    case 'savings_pattern_thin':
      return ReasonInsight(
        code: code,
        title: 'Savings pattern is not yet consistent',
        detail:
            'Confirmed savings total is ${_formatCurrency(dashboard.groupTotal)} RWF with an average contribution of ${_formatCurrency(dashboard.averageGroupContribution)} RWF.',
        action:
            'Build a steadier savings pattern with repeated confirmed contributions.',
        icon: Icons.savings_outlined,
        color: AppColors.blue,
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
        color: AppColors.orange,
      );
    case 'group_activity_low':
      return ReasonInsight(
        code: code,
        title: 'Group contribution activity is still light',
        detail:
            '${dashboard.groupContributionCount} confirmed contributions were counted. More months with group contributions strengthen group reliability.',
        action:
            'Increase the number of months with confirmed group contributions.',
        icon: Icons.groups_outlined,
        color: AppColors.yellow,
      );
    case 'profile_verification_needed':
      return ReasonInsight(
        code: code,
        title: 'Profile verification is holding the score back',
        detail:
            'Official identity signals are not fully complete yet. Current KYC status is ${_kycStatusLabel(dashboard.kycStatus).toLowerCase()}.',
        action: 'Complete official-name, phone, and KYC verification.',
        icon: Icons.badge_outlined,
        color: AppColors.purple,
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
        color: AppColors.accent,
      );
  }
}
