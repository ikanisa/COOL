import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';


import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/partner.dart';
import '../widgets/partner_brand_mark.dart';
import 'bank_partner_config.dart';
import 'partner_shared_widgets.dart';

// ═════════════════════════════════════════════════════════════════════════════
// BANK HERO
// ═════════════════════════════════════════════════════════════════════════════

class BankHero extends StatelessWidget {
  const BankHero({required this.partner, required this.config, super.key});

  final Partner partner;
  final BankPartnerConfig config;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.accentGradient,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      'Official Partner',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PartnerBrandMark(
                  partner: partner,
                  width: 138,
                  height: 72,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              partner.name,
              style: GoogleFonts.dmSans(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              config.description,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// QUICK ACTION GRID
// ═════════════════════════════════════════════════════════════════════════════

class BankQuickActionGrid extends StatelessWidget {
  const BankQuickActionGrid({
    required this.partner,
    required this.config,
    super.key,
  });

  final Partner partner;
  final BankPartnerConfig config;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final action in config.quickActions)
          PartnerQuickActionTile(
            icon: action.icon,
            title: action.title,
            subtitle: action.subtitle,
            onTap: () =>
                launchPartnerAction(context, partner, action: action.action),
          ),
      ],
    );
  }
}

Future<void> launchPartnerAction(
  BuildContext context,
  Partner partner, {
  required String action,
}) async {
  switch (action.trim()) {
    case 'internal:group_savings':
      context.push('/groups/create');
      return;
    case 'internal:get_loan':
      context.push('/partners/bank/${partner.slug}/onboarding/loan');
      return;
    case 'internal:open_account':
      context.push('/partners/bank/${partner.slug}/onboarding/account');
      return;
    default:
      CoolToast.info(
        context,
        '${partner.name} partner actions will be available soon.',
      );
  }
}
