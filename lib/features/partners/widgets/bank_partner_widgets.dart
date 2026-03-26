import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
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
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      useGradient: false,
      backgroundColor: colors.cardSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BANK PARTNER',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  partner.name,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                    letterSpacing: -0.8,
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
          const SizedBox(height: CoolSpace.x4),
          Text(
            partner.description ?? 'Trusted financial partner.',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              height: 1.25,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          const Wrap(
            spacing: CoolSpace.x2,
            runSpacing: CoolSpace.x2,
            children: [
              PartnerHeroPill(
                icon: Icons.savings_rounded,
                label: 'Custodian-led savings',
              ),
              PartnerHeroPill(
                icon: Icons.account_balance_rounded,
                label: 'Bank collections oversight',
              ),
            ],
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

  static const _supportedActions = {
    'internal:group_savings',
    'internal:group_savings_custodian',
  };

  static const _fallbackTile = _BankCta(
    action: 'internal:group_savings_custodian',
    title: 'Group Savings Custodian',
    subtitle: 'Launch a bank-custodied savings group',
    icon: Icons.savings_rounded,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    final matchedService = services.cast<PartnerService?>().firstWhere(
      (service) => _supportedActions.contains(service?.ctaAction?.trim()),
      orElse: () => null,
    );
    final action = _ResolvedBankCta(
      fallback: _fallbackTile,
      service: matchedService,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GROUP SAVINGS CUSTODIAN',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: CoolSpace.x3),
        CoolCard(
          useGradient: false,
          backgroundColor: colors.cardSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(action.fallback.icon, color: colors.accent, size: 24),
              const SizedBox(height: CoolSpace.x4),
              Text(
                action.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                action.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: CoolSpace.x6),
              CoolButton(
                label: 'Open custodian flow',
                fullWidth: false,
                icon: action.fallback.icon,
                onTap: () => launchPartnerAction(
                  context,
                  partner,
                  action: action.fallback.action,
                ),
              ),
            ],
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

class _ResolvedBankCta {
  const _ResolvedBankCta({required this.fallback, required this.service});

  final _BankCta fallback;
  final PartnerService? service;

  String get title => service?.title ?? fallback.title;
  String get subtitle => service?.subtitle ?? fallback.subtitle;
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
    CoolToast.info(
      context,
      'Dialing ${normalized.replaceFirst('ussd:', '')}...',
    );
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
    case 'internal:group_savings_custodian':
    case 'internal:group_savings':
      context.push('/groups/create');
      return;
    default:
      CoolToast.info(
        context,
        '${partner.name} partner actions will be available soon.',
      );
  }
}
