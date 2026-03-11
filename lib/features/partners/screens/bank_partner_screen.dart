import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../models/partner.dart';
import '../models/partner_service.dart';
import '../providers/partner_provider.dart';
import '../providers/partner_service_provider.dart';

const _urwegoProductsUrl = 'https://www.urwegofinance.com/productsandservices/';
const _urwegoInternetBankingUrl = 'https://internetbanking.urwegofinance.com/';
const _urwegoLocationsUrl = 'https://www.urwegofinance.com/our-locations/';
const _urwegoSupportEmail = 'info@urwegofinance.com';
const _urwegoPhone = '+250788173100';
const _urwegoHotline = '5151';
const _urwegoWhatsApp = '+250785083323';

const _equityHomeUrl = 'https://equitygroupholdings.com/rw/home/';
const _equityOpenAccountUrl =
    'https://equitygroupholdings.com/rw/open-an-account/';
const _equityPayAndSendMoneyUrl =
    'https://equitygroupholdings.com/rw/pay-and-send-money/';
const _equitySaveAndInvestUrl =
    'https://equitygroupholdings.com/rw/save-and-invest/';
const _equityTalkToUsUrl = 'https://equitygroupholdings.com/rw/talk-to-us/';
const _equitySupportEmail = 'talktous@equitybank.co.rw';
const _equityPhone = '+250737360000';
const _equityHotline = '4555';

const _bankCategoryOrder = <String>[
  'digital',
  'payments',
  'current_account',
  'savings',
  'group_account',
  'group_loan',
  'business_loan',
  'agri',
  'support',
];

const _bankCategoryMeta = <String, _BankCategoryMeta>{
  'digital': _BankCategoryMeta(
    title: 'Digital Banking',
    description:
        'Mobile, online, and self-service channels published by each bank partner.',
    icon: Icons.phonelink_ring_rounded,
    accent: AppColors.blue,
  ),
  'payments': _BankCategoryMeta(
    title: 'Transfers & Remittances',
    description:
        'Move money locally and internationally through bank, SWIFT, and remittance rails.',
    icon: Icons.swap_horiz_rounded,
    accent: AppColors.accent,
  ),
  'current_account': _BankCategoryMeta(
    title: 'Accounts',
    description:
        'Personal, SME, corporate, student, group, and diaspora account entry points.',
    icon: Icons.account_balance_wallet_outlined,
    accent: AppColors.orange,
  ),
  'savings': _BankCategoryMeta(
    title: 'Savings',
    description:
        'Flexible and term savings options for households, children, and longer-term goals.',
    icon: Icons.savings_outlined,
    accent: AppColors.accent,
  ),
  'group_account': _BankCategoryMeta(
    title: 'Group & Community Banking',
    description:
        'Community, association, youth, and solidarity-group banking products.',
    icon: Icons.groups_2_outlined,
    accent: AppColors.orange,
  ),
  'group_loan': _BankCategoryMeta(
    title: 'Group Loans',
    description:
        'Community-banking loan products for organized groups and village savings associations.',
    icon: Icons.diversity_3_outlined,
    accent: AppColors.orange,
  ),
  'business_loan': _BankCategoryMeta(
    title: 'Borrowing & Credit',
    description:
        'Personal, SME, asset-finance, mortgage, and working-capital borrowing paths.',
    icon: Icons.storefront_outlined,
    accent: AppColors.red,
  ),
  'agri': _BankCategoryMeta(
    title: 'Agricultural Finance',
    description:
        'Seasonal and value-chain finance across coffee, maize, rice, and Irish potato products.',
    icon: Icons.agriculture_outlined,
    accent: AppColors.whatsapp,
  ),
  'support': _BankCategoryMeta(
    title: 'Support & Onboarding',
    description:
        'Official channels, locations, and contact points for opening or managing services.',
    icon: Icons.support_agent_rounded,
    accent: AppColors.whatsapp,
  ),
};

const _bankPartnerConfigs = <String, _BankPartnerConfig>{
  'urwego': _BankPartnerConfig(
    sourceTitle: 'Official Urwego content',
    sourceDescription:
        'This page is backed by Supabase partner data refreshed from Urwego Finance official products, contact, about, and locations pages.',
    defaultDescription:
        'Urwego Finance provides digital banking, savings, credit, transfers, and support channels for households, groups, and small businesses in Rwanda.',
    heroTags: [
      _BankHeroTagData(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Accounts & Savings',
      ),
      _BankHeroTagData(
        icon: Icons.trending_up_rounded,
        label: 'Group & SME Credit',
      ),
      _BankHeroTagData(
        icon: Icons.phone_android_rounded,
        label: 'mHose + Internet Banking',
      ),
    ],
    quickActions: [
      _BankQuickActionData(
        icon: Icons.public_rounded,
        title: 'Products',
        subtitle: 'Official products and services',
        action: 'web:$_urwegoProductsUrl',
      ),
      _BankQuickActionData(
        icon: Icons.laptop_mac_rounded,
        title: 'Internet Banking',
        subtitle: 'Open the online banking portal',
        action: 'web:$_urwegoInternetBankingUrl',
      ),
      _BankQuickActionData(
        icon: Icons.phone_in_talk_rounded,
        title: 'Call Urwego',
        subtitle: 'Hotline $_urwegoHotline',
        action: 'tel:$_urwegoPhone',
      ),
      _BankQuickActionData(
        icon: Icons.location_on_outlined,
        title: 'Locations',
        subtitle: 'Branches and mHose agents',
        action: 'web:$_urwegoLocationsUrl',
      ),
    ],
    supportHeading: 'Need help choosing a service?',
    supportDescription:
        'Use Urwego Finance official contact points for onboarding, product questions, and branch support.',
    supportItems: [
      _BankSupportItemData(
        icon: Icons.phone_outlined,
        label: 'Phone',
        value: '5151 / +250 788 173 100',
      ),
      _BankSupportItemData(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'WhatsApp',
        value: '+250 785 083 323',
      ),
      _BankSupportItemData(
        icon: Icons.alternate_email_rounded,
        label: 'Email',
        value: _urwegoSupportEmail,
      ),
      _BankSupportItemData(
        icon: Icons.place_outlined,
        label: 'Head office',
        value: 'CHIC Building, Kicukiro, Kigali',
      ),
    ],
    supportButtons: [
      _BankSupportButtonData(
        label: 'Chat on WhatsApp',
        action: 'whatsapp:$_urwegoWhatsApp',
      ),
      _BankSupportButtonData(
        label: 'Email Urwego',
        action: 'mailto:$_urwegoSupportEmail',
      ),
    ],
  ),
  'equity': _BankPartnerConfig(
    sourceTitle: 'Official Equity Rwanda content',
    sourceDescription:
        'This page is backed by Supabase partner data refreshed from Equity Bank Rwanda official home, account, payments, savings, borrowing, and contact pages.',
    defaultDescription:
        'Equity Bank Rwanda offers personal, SME, corporate, group, and diaspora banking, plus digital channels, savings, payments, and borrowing services in Rwanda.',
    heroTags: [
      _BankHeroTagData(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Accounts & Payments',
      ),
      _BankHeroTagData(icon: Icons.savings_outlined, label: 'Save & Borrow'),
      _BankHeroTagData(
        icon: Icons.phone_android_rounded,
        label: 'Equity Mobile + EazzyBiz',
      ),
    ],
    quickActions: [
      _BankQuickActionData(
        icon: Icons.person_add_alt_1_rounded,
        title: 'Open Account',
        subtitle: 'Personal, SME, group, diaspora',
        action: 'web:$_equityOpenAccountUrl',
      ),
      _BankQuickActionData(
        icon: Icons.swap_horiz_rounded,
        title: 'Pay & Send',
        subtitle: 'Transfers and payment services',
        action: 'web:$_equityPayAndSendMoneyUrl',
      ),
      _BankQuickActionData(
        icon: Icons.savings_outlined,
        title: 'Save & Invest',
        subtitle: 'Savings and deposit products',
        action: 'web:$_equitySaveAndInvestUrl',
      ),
      _BankQuickActionData(
        icon: Icons.support_agent_rounded,
        title: 'Talk to Us',
        subtitle: 'Customer care and support',
        action: 'web:$_equityTalkToUsUrl',
      ),
    ],
    supportHeading: 'Need Equity Rwanda support?',
    supportDescription:
        'Use Equity Bank Rwanda official contact points for account opening, digital banking help, payments, savings, and borrowing support.',
    supportItems: [
      _BankSupportItemData(
        icon: Icons.phone_outlined,
        label: 'Customer care',
        value: '$_equityHotline / +250 737 360 000',
      ),
      _BankSupportItemData(
        icon: Icons.alternate_email_rounded,
        label: 'Email',
        value: _equitySupportEmail,
      ),
      _BankSupportItemData(
        icon: Icons.schedule_outlined,
        label: 'Service hours',
        value: 'Weekdays 8:00-18:00 · Weekends 9:00-13:00',
      ),
      _BankSupportItemData(
        icon: Icons.public_rounded,
        label: 'Website',
        value: _equityHomeUrl,
      ),
    ],
    supportButtons: [
      _BankSupportButtonData(label: 'Call Equity', action: 'tel:$_equityPhone'),
      _BankSupportButtonData(
        label: 'Email Equity',
        action: 'mailto:$_equitySupportEmail',
      ),
    ],
  ),
};

_BankPartnerConfig _bankConfigForSlug(String slug) {
  return _bankPartnerConfigs[slug] ?? _bankPartnerConfigs['urwego']!;
}

String _normalizeBankCategory(String rawCategory) {
  return switch (rawCategory.trim().toLowerCase()) {
    'digital' => 'digital',
    'payment' ||
    'payments' ||
    'transfer' ||
    'transfers' ||
    'remittance' => 'payments',
    'current_account' || 'account' => 'current_account',
    'savings' => 'savings',
    'group_account' => 'group_account',
    'group_loan' => 'group_loan',
    'business_loan' || 'loan' => 'business_loan',
    'agri' || 'agriculture' || 'agricultural' => 'agri',
    'support' || 'service' || 'general' => 'support',
    _ => 'support',
  };
}

List<MapEntry<String, List<PartnerService>>> _groupBankServices(
  List<PartnerService> services,
) {
  final buckets = <String, List<PartnerService>>{};
  for (final service in services) {
    final category = _normalizeBankCategory(service.category);
    buckets.putIfAbsent(category, () => <PartnerService>[]).add(service);
  }

  final grouped = <MapEntry<String, List<PartnerService>>>[];
  for (final category in _bankCategoryOrder) {
    final bucket = buckets.remove(category);
    if (bucket != null && bucket.isNotEmpty) {
      grouped.add(MapEntry(category, bucket));
    }
  }
  for (final extra in buckets.entries) {
    if (extra.value.isNotEmpty) {
      grouped.add(extra);
    }
  }
  return grouped;
}

Future<void> _launchExternalUri(
  BuildContext context,
  Uri uri, {
  String unavailableMessage = 'This action is not available on this device.',
  String failureMessage = 'Could not open this action right now.',
}) async {
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(unavailableMessage)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}

Future<void> _launchPartnerAction(
  BuildContext context,
  Partner partner, {
  required String action,
  String? topic,
}) async {
  final normalizedAction = action.trim();
  if (normalizedAction.isEmpty) {
    return;
  }

  if (normalizedAction == 'whatsapp' ||
      normalizedAction.startsWith('whatsapp:')) {
    final explicitPhone = normalizedAction.startsWith('whatsapp:')
        ? normalizedAction.substring('whatsapp:'.length).trim()
        : '';
    final phone = explicitPhone.isNotEmpty
        ? explicitPhone
        : partner.whatsappNumber?.trim() ?? '';
    if (phone.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No WhatsApp channel is configured for ${partner.name}.',
            ),
          ),
        );
      }
      return;
    }
    final message = switch (topic) {
      null => 'Hello, I would like help with ${partner.name}.',
      _ => 'Hello, I would like help with ${partner.name}: $topic.',
    };
    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phone,
      message: message,
    );
    return;
  }

  if (normalizedAction.startsWith('route:')) {
    final route = normalizedAction.substring('route:'.length);
    const allowedPrefixes = [
      '/groups',
      '/mobility',
      '/partners',
      '/profile',
      '/settings',
    ];
    final isAllowed = allowedPrefixes.any(
      (prefix) => route == prefix || route.startsWith('$prefix/'),
    );
    if (isAllowed && context.mounted) {
      context.go(route);
    } else {
      debugPrint('[BankPartner] Blocked unknown CTA route: $route');
    }
    return;
  }

  if (normalizedAction.startsWith('ussd:')) {
    final encoded = Uri.encodeComponent(
      normalizedAction.substring('ussd:'.length),
    );
    await _launchExternalUri(
      context,
      Uri.parse('tel:$encoded'),
      unavailableMessage: 'Could not open the dialer for this USSD code.',
      failureMessage:
          'Could not launch the ${partner.name} USSD flow right now.',
    );
    return;
  }

  if (normalizedAction.startsWith('web:')) {
    final url = normalizedAction.substring('web:'.length);
    await _launchExternalUri(
      context,
      Uri.parse(url),
      unavailableMessage: 'Could not open the official website.',
      failureMessage: 'Could not launch ${partner.name} website right now.',
    );
    return;
  }

  if (normalizedAction.startsWith('tel:')) {
    await _launchExternalUri(
      context,
      Uri.parse(normalizedAction),
      unavailableMessage: 'Could not open the dialer.',
      failureMessage: 'Could not call ${partner.name} right now.',
    );
    return;
  }

  if (normalizedAction.startsWith('mailto:')) {
    await _launchExternalUri(
      context,
      Uri.parse(normalizedAction),
      unavailableMessage: 'No mail app is available on this device.',
      failureMessage: 'Could not open the email app right now.',
    );
  }
}

class BankPartnerScreen extends ConsumerWidget {
  const BankPartnerScreen({required this.bankId, super.key});

  final String bankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(partnerBySlugProvider(bankId));

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.text,
            onPressed: () => context.pop(),
          ),
          title: partnerAsync.when(
            data: (partner) => Text(
              partner?.name ?? 'Partner',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => Text(
              'Partner',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          centerTitle: true,
        ),
        body: partnerAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(18),
            child: CoolSkeletonList(),
          ),
          error: (error, _) => _ErrorBody(
            message: error.toString(),
            onRetry: () => ref.invalidate(partnerBySlugProvider(bankId)),
          ),
          data: (partner) {
            if (partner == null) {
              return const _ErrorBody(message: 'Partner not found');
            }
            return _BankBody(partner: partner);
          },
        ),
      ),
    );
  }
}

class _BankBody extends ConsumerWidget {
  const _BankBody({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = _bankConfigForSlug(partner.slug);
    final servicesAsync = ref.watch(partnerServicesProvider(partner.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BankHero(partner: partner, config: config),
          const SizedBox(height: 16),
          _QuickActionGrid(partner: partner, config: config),
          const SizedBox(height: 16),
          _SourceCard(config: config),
          const SizedBox(height: 18),
          servicesAsync.when(
            loading: () => const CoolSkeletonList(itemCount: 5),
            error: (e, _) => _ErrorCard(message: e.toString()),
            data: (services) {
              if (services.isEmpty) {
                return _EmptyServicesCard(partnerName: partner.name);
              }

              final grouped = _groupBankServices(services);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in grouped) ...[
                    _BankSectionHeader(category: group.key),
                    const SizedBox(height: 12),
                    for (final service in group.value) ...[
                      _ServiceCard(service: service, partner: partner),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _SupportCard(partner: partner, config: config),
        ],
      ),
    );
  }
}

class _BankHero extends StatelessWidget {
  const _BankHero({required this.partner, required this.config});

  final Partner partner;
  final _BankPartnerConfig config;

  @override
  Widget build(BuildContext context) {
    final description = partner.description ?? config.defaultDescription;

    return CoolCard(
      gradient: AppColors.accentGradient,
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -6,
            child: Text(
              partner.emoji,
              style: TextStyle(
                fontSize: 82,
                color: Colors.white.withValues(alpha: 0.08),
              ),
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
                  child: Text(
                    '${partner.emoji} Official partner content',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
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
                      _HeroTag(icon: tag.icon, label: tag.label),
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

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.partner, required this.config});

  final Partner partner;
  final _BankPartnerConfig config;

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
          _QuickActionTile(
            icon: action.icon,
            title: action.title,
            subtitle: action.subtitle,
            onTap: () =>
                _launchPartnerAction(context, partner, action: action.action),
          ),
      ],
    );
  }
}

class _BankSectionHeader extends StatelessWidget {
  const _BankSectionHeader({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final meta = _bankCategoryMeta[category] ?? _bankCategoryMeta['support']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: meta.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(meta.icon, size: 18, color: meta.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                meta.title,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          meta.description,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.partner});

  final PartnerService service;
  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final normalizedCategory = _normalizeBankCategory(service.category);
    final meta =
        _bankCategoryMeta[normalizedCategory] ?? _bankCategoryMeta['support']!;

    return CoolCard(
      gradient: normalizedCategory == 'digital' ? AppColors.blueGradient : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: meta.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  service.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    if (service.subtitle != null &&
                        service.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.subtitle!,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (service.details.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < service.details.length; i++) ...[
                    _DetailRow(detail: service.details[i], accent: meta.accent),
                    if (i < service.details.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
          if (service.ctaLabel != null &&
              service.ctaAction != null &&
              service.ctaAction!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            CoolButton(
              label: service.ctaLabel!,
              onTap: () => _launchPartnerAction(
                context,
                partner,
                action: service.ctaAction!,
                topic: service.title,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.partner, required this.config});

  final Partner partner;
  final _BankPartnerConfig config;

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
            _SupportLine(
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
                    onTap: () => _launchPartnerAction(
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail, required this.accent});

  final ServiceDetail detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(detail.icon, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail.value,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: CoolCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.accent, size: 22),
              const Spacer(),
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.config});

  final _BankPartnerConfig config;

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

class _SupportLine extends StatelessWidget {
  const _SupportLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyServicesCard extends StatelessWidget {
  const _EmptyServicesCard({required this.partnerName});

  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        children: [
          const Text('📋', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            'No services listed yet',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Services for $partnerName will appear here once they are configured by an admin.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            'Unable to load services',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              CoolButton(label: 'Retry', onTap: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}

class _BankCategoryMeta {
  const _BankCategoryMeta({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
}

class _BankPartnerConfig {
  const _BankPartnerConfig({
    required this.sourceTitle,
    required this.sourceDescription,
    required this.defaultDescription,
    required this.heroTags,
    required this.quickActions,
    required this.supportHeading,
    required this.supportDescription,
    required this.supportItems,
    required this.supportButtons,
  });

  final String sourceTitle;
  final String sourceDescription;
  final String defaultDescription;
  final List<_BankHeroTagData> heroTags;
  final List<_BankQuickActionData> quickActions;
  final String supportHeading;
  final String supportDescription;
  final List<_BankSupportItemData> supportItems;
  final List<_BankSupportButtonData> supportButtons;
}

class _BankHeroTagData {
  const _BankHeroTagData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _BankQuickActionData {
  const _BankQuickActionData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
}

class _BankSupportItemData {
  const _BankSupportItemData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _BankSupportButtonData {
  const _BankSupportButtonData({required this.label, required this.action});

  final String label;
  final String action;
}
