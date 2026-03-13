import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/momo_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import 'driver_profile_models.dart';

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
    return CoolCard(
      gradient: AppColors.blueGradient,
      borderColor: AppColors.blue.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unlock Unlimited Trips',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$tripsUsedCount trips posted · $freeTripsRemaining credits remaining.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          CoolButton(
            label: 'Pay via MOMO USSD',
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
    final borderColor = isSelected
        ? AppColors.accent
        : isFeatured
        ? AppColors.blue
        : AppColors.border;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${plan.displayName} plan',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.accentGlow
                : AppColors.surface2.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: isSelected || isFeatured ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(IconMapper.from(plan.emoji), size: 24, color: AppColors.text2),
              const SizedBox(height: 8),
              Text(
                plan.displayName,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatAmount(plan.amountRwf)} RWF',
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppColors.accent : AppColors.blue,
                ),
              ),
              Text(
                '/month',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text3,
                ),
              ),
            ],
          ),
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
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accentGlow, AppColors.surface2],
      ),
      borderColor: AppColors.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.verified_rounded,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.plan.displayName,
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatAmount(subscription.plan.amountRwf)} RWF · '
                      'Expires ${formatDate(subscription.expiresAt)}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$daysRemaining days remaining',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.surface3,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
