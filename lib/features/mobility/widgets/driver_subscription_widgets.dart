import 'package:flutter/material.dart';

import '../../../core/services/momo_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import 'driver_profile_models.dart';
import '../../../core/l10n/l10n.dart';

/// Full-width banner prompting upgrade to a paid subscription plan.
class DriverSubscriptionBanner extends StatelessWidget {
  const DriverSubscriptionBanner({
    required this.tripsUsedCount,
    required this.freeTripsRemaining,
    required this.selectedPlan,
    required this.isLoading,
    required this.onPlanSelected,
    required this.onPayTap,
    super.key,
  });

  final int tripsUsedCount;
  final int freeTripsRemaining;
  final SubscriptionPlan selectedPlan;
  final bool isLoading;
  final ValueChanged<SubscriptionPlan> onPlanSelected;
  final VoidCallback onPayTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.info.withValues(alpha: 0.35),
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unlock Unlimited Trips',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$tripsUsedCount trips posted. $freeTripsRemaining free left.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Row(
            children: [
              Expanded(
                child: DriverPlanCard(
                  plan: MomoService.motoTaxiPlan,
                  isSelected: selectedPlan == MomoService.motoTaxiPlan,
                  isFeatured: false,
                  onTap: () => onPlanSelected(MomoService.motoTaxiPlan),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DriverPlanCard(
                  plan: MomoService.cabOtherPlan,
                  isSelected: selectedPlan == MomoService.cabOtherPlan,
                  isFeatured: true,
                  onTap: () => onPlanSelected(MomoService.cabOtherPlan),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(
            label: context.l10n.payViaMomoUssd1,
            isLoading: isLoading,
            onTap: onPayTap,
          ),
        ],
      ),
    );
  }
}

/// Individual plan selection card inside the subscription banner.
class DriverPlanCard extends StatelessWidget {
  const DriverPlanCard({
    required this.plan,
    required this.isSelected,
    required this.isFeatured,
    required this.onTap,
    super.key,
  });

  final SubscriptionPlan plan;
  final bool isSelected;
  final bool isFeatured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final borderColor = isSelected
        ? colors.accent
        : isFeatured
        ? colors.info
        : colors.border;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${plan.displayName} plan',
      child: CoolCard(
        onTap: onTap,
        semanticsLabel: '${plan.displayName} plan',
        padding: const EdgeInsets.all(14),
        backgroundColor: isSelected
            ? colors.chipSelectedBackground
            : colors.cardSurfaceStrong,
        borderColor: borderColor,
        useGradient: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.accent.withValues(alpha: 0.12)
                    : colors.inputSurface,
                borderRadius: BorderRadius.circular(CoolRadii.md),
              ),
              alignment: Alignment.center,
              child: Icon(
                plan.icon,
                size: 20,
                color: isSelected ? colors.accent : colors.secondaryText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              plan.displayName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: CoolSpace.x1),
            Text(
              '${formatAmount(plan.amountRwf)} RWF',
              style: text.mono(
                theme.textTheme.titleSmall,
                color: isSelected ? colors.accent : colors.info,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '/month',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.tertiaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Active subscription card with progress bar and days remaining.
class ActiveSubscriptionCard extends StatelessWidget {
  const ActiveSubscriptionCard({
    required this.subscription,
    required this.now,
    super.key,
  });

  final DriverSubscription subscription;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final totalDays = subscription.expiresAt
        .difference(subscription.startedAt)
        .inDays
        .clamp(1, 365);
    final daysRemaining = subscription.expiresAt
        .difference(now)
        .inDays
        .clamp(0, totalDays);
    final progress = daysRemaining / totalDays;

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.success.withValues(alpha: 0.35),
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.chipSelectedBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.verified_rounded, color: colors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.plan.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primaryText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${formatAmount(subscription.plan.amountRwf)} RWF',
                          style: text.mono(
                            theme.textTheme.bodySmall,
                            color: colors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Expires ${formatDate(subscription.expiresAt)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.secondaryText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$daysRemaining days remaining',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colors.inputSurface,
              color: colors.success,
            ),
          ),
        ],
      ),
    );
  }
}
