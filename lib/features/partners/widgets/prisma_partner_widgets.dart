import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/partner.dart';
import 'partner_shared_widgets.dart';
import 'prisma_partner_config.dart';

// ═════════════════════════════════════════════════════════════════════════════
// HERO CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaHeroCard extends StatelessWidget {
  const PrismaHeroCard({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final description =
        partner.description ??
        'AI professional services Rwanda';

    return CoolCard(
      gradient: AppColors.accentGradient,
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -8,
            child: Icon(
              IconMapper.from(partner.emoji),
              size: 84,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        IconMapper.from(partner.emoji),
                        size: 13,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Official IKANISA content',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
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
                const SizedBox(height: 4),
                Text(
                  partner.subtitle ?? 'IKANISA AI professional services',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
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
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    PartnerHeroPill(
                      icon: Icons.balance_outlined,
                      label: 'Legal, Tax & Compliance',
                    ),
                    PartnerHeroPill(
                      icon: Icons.assured_workload_outlined,
                      label: 'Audit, Insurance & Risk',
                    ),
                    PartnerHeroPill(
                      icon: Icons.flag_outlined,
                      label: 'Rwanda Jurisdiction',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// QUICK ACTIONS
// ═════════════════════════════════════════════════════════════════════════════

class PrismaQuickActions extends StatelessWidget {
  const PrismaQuickActions({required this.partner, super.key});

  final Partner partner;

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
        PartnerQuickActionTile(
          icon: Icons.public_rounded,
          title: 'Website',
          subtitle: 'Open ikanisa.com',
          onTap: () => launchPrismaAction(
            context,
            partner,
            action: 'web:$ikanisaSiteUrl',
          ),
        ),
        PartnerQuickActionTile(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Rwanda Desk',
          subtitle: 'WhatsApp Rwanda team',
          onTap: () => launchPrismaAction(
            context,
            partner,
            action: 'whatsapp:$ikanisaRwandaWhatsApp',
          ),
        ),
        PartnerQuickActionTile(
          icon: Icons.alternate_email_outlined,
          title: 'Email',
          subtitle: ikanisaEmail,
          onTap: () => launchPrismaAction(
            context,
            partner,
            action: 'mailto:$ikanisaEmail',
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// STATS CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaStatsCard extends StatelessWidget {
  const PrismaStatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'IKANISA at a glance',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              PrismaStatTile(value: '9', label: 'AI Agents'),
              SizedBox(width: 10),
              PrismaStatTile(value: '28K+', label: 'Indexed Docs'),
              SizedBox(width: 10),
              PrismaStatTile(value: '1', label: 'Jurisdiction'),
              SizedBox(width: 10),
              PrismaStatTile(value: '14', label: 'Sectors'),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// VALUES CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaValuesCard extends StatelessWidget {
  const PrismaValuesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How the platform works',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These are the core',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          for (final item in prismaValues) ...[
            PrismaValueRow(
              icon: item.icon,
              title: item.title,
              description: item.description,
            ),
            if (item != prismaValues.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SUPPORT CARD
// ═════════════════════════════════════════════════════════════════════════════

class PrismaSupportCard extends StatelessWidget {
  const PrismaSupportCard({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.blueGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get in touch',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Reach the IKANISA Rwanda',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const PartnerSupportLine(
            icon: Icons.flag_outlined,
            label: 'Rwanda WhatsApp',
            value: '+250 795 588 248',
          ),
          const SizedBox(height: 10),
          const PartnerSupportLine(
            icon: Icons.alternate_email_outlined,
            label: 'Email',
            value: ikanisaEmail,
          ),
          const SizedBox(height: 10),
          const PartnerSupportLine(
            icon: Icons.place_outlined,
            label: 'Coverage',
            value: 'Kigali, Rwanda',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 180,
            child: CoolButton(
              label: 'Open Rwanda Desk',
              onTap: () => launchPrismaAction(
                context,
                partner,
                action: 'whatsapp:$ikanisaRwandaWhatsApp',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PRISMA-SPECIFIC SMALL WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class PrismaValueRow extends StatelessWidget {
  const PrismaValueRow({
    required this.icon,
    required this.title,
    required this.description,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
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
    );
  }
}

class PrismaStatTile extends StatelessWidget {
  const PrismaStatTile({required this.value, required this.label, super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
