import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../auth/models/user_profile.dart';
import '../models/credit_dashboard.dart';
import '../models/credit_readiness.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

String kycStatusLabel(String status) {
  return switch (status) {
    'verified' => 'Verified',
    'pending_review' => 'Pending review',
    'rejected' => 'Rejected',
    _ => 'Unverified',
  };
}

// ── Widgets ──────────────────────────────────────────────────────────────

/// Hero "next move" card at the top of the readiness screen.
class ReadinessNextMoveCard extends StatelessWidget {
  const ReadinessNextMoveCard({
    required this.report,
    required this.dashboard,
    required this.user,
    super.key,
  });

  final CreditReadinessReport report;
  final CreditDashboard? dashboard;
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final needsProfileWork =
        report.accountOpening.state == CreditReadinessState.actionNeeded ||
        report.loanApplication.state == CreditReadinessState.actionNeeded;
    final partnerReady =
        report.loanApplication.state == CreditReadinessState.ready ||
        report.loanApplication.state == CreditReadinessState.nearlyReady ||
        report.accountOpening.state == CreditReadinessState.ready ||
        report.accountOpening.state == CreditReadinessState.nearlyReady;

    final headline = needsProfileWork
        ? 'Tighten the profile first'
        : partnerReady
        ? 'The user can move to partners'
        : 'Keep building verified financial history';
    final detail = needsProfileWork
        ? report.accountOpening.nextStep
        : partnerReady
        ? report.loanApplication.nextStep
        : 'Let wallet, savings, and KYC evidence mature first.';

    return CoolCard(
      borderColor: AppColors.purple.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next step',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            headline,
            style: GoogleFonts.dmSans(
              fontSize: 20,
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              HistoryStatChip(
                label: 'KYC',
                value: kycStatusLabel(user.kycStatus),
              ),
              HistoryStatChip(
                label: 'Score',
                value: dashboard?.score?.toString() ?? 'Pending',
              ),
              HistoryStatChip(
                label: 'Checks',
                value: '${report.completedChecks}/${report.totalChecks}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: needsProfileWork ? 'Open profile' : 'Browse partners',
                  icon: needsProfileWork
                      ? Icons.person_outline_rounded
                      : Icons.account_balance_rounded,
                  onTap: () => context.push(
                    needsProfileWork ? AppRoutes.profile : AppRoutes.partners,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Readiness checks checklist card.
class ReadinessChecklistCard extends StatelessWidget {
  const ReadinessChecklistCard({required this.report, super.key});

  final CreditReadinessReport report;

  @override
  Widget build(BuildContext context) {
    final visibleChecks = report.checks
        .where((check) => !check.isComplete)
        .take(3)
        .toList(growable: false);
    final checksToShow = visibleChecks.isNotEmpty
        ? visibleChecks
        : report.checks.take(2).toList(growable: false);
    final hiddenCount = report.checks.length - checksToShow.length;

    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Readiness checks',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${report.completedChecks}/${report.totalChecks} checks complete',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            report.blockingIssues == 0
                ? 'No blocking issues open.'
                : '${report.blockingIssues} blockers need attention.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          ...checksToShow.map(
            (check) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChecklistRow(check: check),
            ),
          ),
          if (hiddenCount > 0)
            Text(
              '+$hiddenCount more checks',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text3,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.check});

  final CreditReadinessCheck check;

  @override
  Widget build(BuildContext context) {
    final color = check.isComplete
        ? AppColors.accent
        : (check.isBlocking ? AppColors.orange : AppColors.text3);
    final icon = check.isComplete
        ? Icons.check_circle_rounded
        : (check.isBlocking
              ? Icons.error_outline_rounded
              : Icons.radio_button_unchecked_rounded);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: check.isComplete
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.border2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        check.label,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (check.isBlocking)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Required',
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  check.detail,
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

/// Stat chip (kyc, score, checks, dates).
class HistoryStatChip extends StatelessWidget {
  const HistoryStatChip({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

// ── State widgets ────────────────────────────────────────────────────────

/// Loading state for readiness.
class ReadinessLoadingState extends StatelessWidget {
  const ReadinessLoadingState({super.key});

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

/// Error state for readiness.
class ReadinessErrorState extends StatelessWidget {
  const ReadinessErrorState({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: CoolCard(child: CoolErrorView(message: error, compact: true)),
    );
  }
}

/// Empty state (user not signed in).
class ReadinessEmptyState extends StatelessWidget {
  const ReadinessEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: CoolCard(
        child: CoolEmptyView(
          message:
              'Sign in to review formal profile, credit, and bank-onboarding readiness.',
          compact: true,
          icon: Icons.credit_score_outlined,
        ),
      ),
    );
  }
}
