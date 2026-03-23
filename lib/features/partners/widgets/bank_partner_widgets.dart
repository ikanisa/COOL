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
                icon: Icons.verified_user_outlined,
                label: 'Secure onboarding',
              ),
              PartnerHeroPill(icon: Icons.bolt_rounded, label: 'Fast approval'),
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    // Filter incoming services to only standard actions, preserving
    // admin-customized titles/subtitles if they exist.
    final matched = <String, PartnerService>{};
    for (final service in services) {
      final action = service.ctaAction?.trim() ?? '';
      if (_standardActions.contains(action) && !matched.containsKey(action)) {
        matched[action] = service;
      }
    }

    final actions = [
      for (final fallback in _fallbackTiles)
        _ResolvedBankCta(fallback: fallback, service: matched[fallback.action]),
    ];
    final primary = actions.first;
    final secondary = actions.skip(1).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'START HERE',
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
              Icon(primary.fallback.icon, color: colors.accent, size: 24),
              const SizedBox(height: CoolSpace.x4),
              Text(
                primary.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CoolSpace.x2),
              Text(
                primary.subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: CoolSpace.x6),
              CoolButton(
                label: 'Continue',
                fullWidth: false,
                icon: primary.fallback.icon,
                onTap: () => launchPartnerAction(
                  context,
                  partner,
                  action: primary.fallback.action,
                ),
              ),
            ],
          ),
        ),
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: CoolSpace.x6),
          Text(
            'MORE SERVICES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          for (var index = 0; index < secondary.length; index++) ...[
            PartnerQuickActionTile(
              icon: secondary[index].fallback.icon,
              title: secondary[index].title,
              subtitle: secondary[index].subtitle,
              onTap: () => launchPartnerAction(
                context,
                partner,
                action: secondary[index].fallback.action,
              ),
            ),
            if (index != secondary.length - 1)
              const SizedBox(height: CoolSpace.x3),
          ],
        ],
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
