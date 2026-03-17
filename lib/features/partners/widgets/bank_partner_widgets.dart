import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/partner.dart';
import '../models/partner_service.dart';
import '../widgets/partner_brand_mark.dart';
import 'partner_shared_widgets.dart';

// ═════════════════════════════════════════════════════════════════════════════
// BANK HERO
// ═════════════════════════════════════════════════════════════════════════════

class BankHero extends StatelessWidget {
  const BankHero({required this.partner, super.key});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  partner.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PartnerBrandMark(
                partner: partner,
                width: 100,
                height: 52,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            partner.description ?? 'Trusted financial partner.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BANK SERVICE GRID
// ═════════════════════════════════════════════════════════════════════════════

class BankServiceGrid extends StatelessWidget {
  const BankServiceGrid({
    required this.partner,
    required this.services,
    super.key,
  });

  final Partner partner;
  final List<PartnerService> services;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const SizedBox.shrink();
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final service in services)
          PartnerQuickActionTile(
            icon: _iconForEmoji(service.emoji),
            title: service.title,
            subtitle: service.subtitle ?? '',
            onTap: () => launchPartnerAction(
              context,
              partner,
              action: service.ctaAction ?? '',
            ),
          ),
      ],
    );
  }

  IconData _iconForEmoji(String emoji) {
    switch (emoji) {
      case '🏦':
      case '🏧':
        return Icons.account_balance_wallet_rounded;
      case '👥':
        return Icons.people_rounded;
      case '📈':
      case '💰':
        return Icons.monetization_on_rounded;
      case '🛡️':
        return Icons.security_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }
}

Future<void> launchPartnerAction(
  BuildContext context,
  Partner partner, {
  required String action,
}) async {
  final normalized = action.trim();
  if (normalized.isEmpty) {
    CoolToast.info(context, 'This service will be available soon.');
    return;
  }

  // Handle internal routes: "route:/groups"
  if (normalized.startsWith('route:')) {
    final route = normalized.replaceFirst('route:', '');
    context.push(route);
    return;
  }

  // Handle USSD: "ussd:*525#"
  if (normalized.startsWith('ussd:')) {
    CoolToast.info(context, 'Dialing ${normalized.replaceFirst('ussd:', '')}...');
    // In a real app, use url_launcher for tel:*...
    return;
  }

  // Handle WhatsApp
  if (normalized == 'whatsapp') {
    CoolToast.info(context, 'Opening WhatsApp chat with ${partner.name}...');
    return;
  }

  // Legacy internal fallback
  switch (normalized) {
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
