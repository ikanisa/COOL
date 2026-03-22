import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
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
    final palette = context.coolPalette;
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
                    color: palette.text,
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
              color: palette.text2,
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

  /// The 3 standard bank CTA actions — no others are allowed.
  static const _standardActions = [
    'internal:open_account',
    'internal:get_loan',
    'internal:group_savings',
  ];

  /// Fallback definitions if the DB doesn't have matching services.
  static const _fallbackTiles = [
    _BankCta(
      action: 'internal:open_account',
      title: 'Open Account',
      subtitle: 'Start banking today',
      icon: Icons.account_balance_rounded,
    ),
    _BankCta(
      action: 'internal:get_loan',
      title: 'Get a Loan',
      subtitle: 'Apply for credit',
      icon: Icons.monetization_on_rounded,
    ),
    _BankCta(
      action: 'internal:group_savings',
      title: 'Group Saving',
      subtitle: 'Save with others',
      icon: Icons.people_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Filter incoming services to only standard actions, preserving
    // admin-customized titles/subtitles if they exist.
    final matched = <String, PartnerService>{};
    for (final service in services) {
      final action = service.ctaAction?.trim() ?? '';
      if (_standardActions.contains(action) && !matched.containsKey(action)) {
        matched[action] = service;
      }
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.0,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final fallback in _fallbackTiles)
          PartnerQuickActionTile(
            icon: fallback.icon,
            title: matched[fallback.action]?.title ?? fallback.title,
            subtitle: matched[fallback.action]?.subtitle ?? fallback.subtitle,
            onTap: () => launchPartnerAction(
              context,
              partner,
              action: fallback.action,
            ),
          ),
      ],
    );
  }
}

class _BankCta {
  const _BankCta({
    required this.action,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String action;
  final String title;
  final String subtitle;
  final IconData icon;
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
