import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_error_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../auth/models/user_profile.dart';
import '../models/credit_dashboard.dart';
import '../models/credit_readiness.dart';

String kycStatusLabel(String status) {
  return switch (status) {
    'verified' => 'Verified',
    'pending_review' => 'Pending review',
    'rejected' => 'Rejected',
    _ => 'Unverified',
  };
}

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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
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
        : 'Build financial history';
    final detail = needsProfileWork
        ? report.accountOpening.nextStep
        : partnerReady
        ? report.loanApplication.nextStep
        : 'Let evidence mature';

    return CoolCard(
      backgroundColor: colors.financialSurface,
      borderColor: colors.info.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next step',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x1 + 2),
          Text(
            headline,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x3 + 2),
          Wrap(
            spacing: CoolSpace.x2 + 2,
            runSpacing: CoolSpace.x2 + 2,
            children: [
              HistoryStatChip(
                label: context.l10n.kyc,
                value: kycStatusLabel(user.kycStatus),
              ),
              HistoryStatChip(
                label: context.l10n.score,
                value: dashboard?.score?.toString() ?? 'Pending',
              ),
              HistoryStatChip(
                label: context.l10n.checks,
                value: '${report.completedChecks}/${report.totalChecks}',
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3 + 2),
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
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
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: CoolSpace.x1 + 2),
          Text(
            '${report.completedChecks}/${report.totalChecks} checks complete',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2 + 2),
          Text(
            report.blockingIssues == 0
                ? 'No blocking issues open.'
                : '${report.blockingIssues} blockers need attention.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x3 + 2),
          ...checksToShow.map(
            (check) => Padding(
              padding: insets.only(bottom: CoolSpace.x2 + 2),
              child: _ChecklistRow(check: check),
            ),
          ),
          if (hiddenCount > 0)
            Text(
              '+$hiddenCount more checks',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w700,
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final insets = context.coolInsets;
    final color = check.isComplete
        ? colors.accent
        : (check.isBlocking ? colors.warning : colors.tertiaryText);
    final icon = check.isComplete
        ? Icons.check_circle_rounded
        : (check.isBlocking
              ? Icons.error_outline_rounded
              : Icons.radio_button_unchecked_rounded);

    return Container(
      width: double.infinity,
      padding: insets.all(CoolSpace.x3),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm - 2)),
        border: Border.all(
          color: check.isComplete
              ? colors.accent.withValues(alpha: 0.18)
              : colors.borderStrong,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: insets.only(top: CoolSpace.x1 / 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: CoolSpace.x2 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        check.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (check.isBlocking)
                      Container(
                        padding: insets.symmetric(
                          horizontal: CoolSpace.x2,
                          vertical: CoolSpace.x1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.12),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(CoolRadii.pill),
                          ),
                        ),
                        child: Text(
                          'Required',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.warning,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  check.detail,
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

/// Stat chip (kyc, score, checks, dates).
class HistoryStatChip extends StatelessWidget {
  const HistoryStatChip({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final insets = context.coolInsets;
    final theme = Theme.of(context);
    return Container(
      padding: insets.symmetric(
        horizontal: CoolSpace.x3 - 2,
        vertical: CoolSpace.x2,
      ),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
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
          const SizedBox(height: CoolSpace.x1 / 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading state for readiness.
class ReadinessLoadingState extends StatelessWidget {
  const ReadinessLoadingState({super.key});

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

/// Error state for readiness.
class ReadinessErrorState extends StatelessWidget {
  const ReadinessErrorState({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: context.coolInsets.symmetric(horizontal: CoolSpace.x6),
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
      padding: context.coolInsets.symmetric(horizontal: CoolSpace.x6),
      child: const CoolCard(
        child: CoolEmptyView(
          message: 'Sign in',
          compact: true,
          icon: Icons.credit_score_outlined,
        ),
      ),
    );
  }
}
