import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
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
    final description = partner.description ?? config.defaultDescription;

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
                      'Official partner content',
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
            if (partner.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                partner.subtitle!,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text2,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              description,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tag in config.heroTags)
                  PartnerHeroPill(icon: tag.icon, label: tag.label),
              ],
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

// ═════════════════════════════════════════════════════════════════════════════
// SUPPORT CARD
// ═════════════════════════════════════════════════════════════════════════════

class BankSupportCard extends StatelessWidget {
  const BankSupportCard({
    required this.partner,
    required this.config,
    super.key,
  });

  final Partner partner;
  final BankPartnerConfig config;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.blueGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            config.supportHeading,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            config.supportDescription,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < config.supportItems.length; i++) ...[
            PartnerSupportLine(
              icon: config.supportItems[i].icon,
              label: config.supportItems[i].label,
              value: config.supportItems[i].value,
            ),
            if (i < config.supportItems.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final button in config.supportButtons)
                SizedBox(
                  width: 180,
                  child: CoolButton(
                    label: button.label,
                    onTap: () => launchPartnerAction(
                      context,
                      partner,
                      action: button.action,
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

// ═════════════════════════════════════════════════════════════════════════════
// SOURCE CARD
// ═════════════════════════════════════════════════════════════════════════════

class BankSourceCard extends StatelessWidget {
  const BankSourceCard({required this.config, super.key});

  final BankPartnerConfig config;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.verified_outlined,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.sourceTitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  config.sourceDescription,
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
