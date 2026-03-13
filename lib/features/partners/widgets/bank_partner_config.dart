import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/partner.dart';
import '../models/partner_service.dart';
import 'partner_shared_widgets.dart';

class BankPartnerConfig {
  const BankPartnerConfig({
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
  final List<BankHeroTagData> heroTags;
  final List<BankQuickActionData> quickActions;
  final String supportHeading;
  final String supportDescription;
  final List<BankSupportItemData> supportItems;
  final List<BankSupportButtonData> supportButtons;
}

class BankHeroTagData {
  const BankHeroTagData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class BankQuickActionData {
  const BankQuickActionData({
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

class BankSupportItemData {
  const BankSupportItemData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class BankSupportButtonData {
  const BankSupportButtonData({required this.label, required this.action});

  final String label;
  final String action;
}

// ═════════════════════════════════════════════════════════════════════════════
// PARTNER URL CONSTANTS
// ═════════════════════════════════════════════════════════════════════════════

const urwegoProductsUrl = 'https://www.urwegofinance.com/productsandservices/';
const urwegoInternetBankingUrl = 'https://internetbanking.urwegofinance.com/';
const urwegoLocationsUrl = 'https://www.urwegofinance.com/our-locations/';
const urwegoSupportEmail = 'info@urwegofinance.com';
const urwegoPhone = '+250788173100';
const urwegoHotline = '5151';
const urwegoWhatsApp = '+250785083323';

const equityHomeUrl = 'https://equitygroupholdings.com/rw/home/';
const equityOpenAccountUrl =
    'https://equitygroupholdings.com/rw/open-an-account/';
const equityPayAndSendMoneyUrl =
    'https://equitygroupholdings.com/rw/pay-and-send-money/';
const equitySaveAndInvestUrl =
    'https://equitygroupholdings.com/rw/save-and-invest/';
const equityTalkToUsUrl = 'https://equitygroupholdings.com/rw/talk-to-us/';
const equitySupportEmail = 'talktous@equitybank.co.rw';
const equityPhone = '+250737360000';
const equityHotline = '4555';

// ═════════════════════════════════════════════════════════════════════════════
// CATEGORY METADATA
// ═════════════════════════════════════════════════════════════════════════════

const bankCategoryOrder = <String>[
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

const bankCategoryMeta = <String, CategoryMeta>{
  'digital': CategoryMeta(
    title: 'Digital Banking',
    description:
        'Mobile, online, and self-service channels published by each bank partner.',
    icon: Icons.phonelink_ring_rounded,
    accent: AppColors.blue,
  ),
  'payments': CategoryMeta(
    title: 'Transfers & Payments',
    description:
        'Move money through MoMo, bank transfers, and payment rails in Rwanda.',
    icon: Icons.swap_horiz_rounded,
    accent: AppColors.accent,
  ),
  'current_account': CategoryMeta(
    title: 'Accounts',
    description:
        'Personal, SME, corporate, student, group, and community account entry points.',
    icon: Icons.account_balance_wallet_outlined,
    accent: AppColors.orange,
  ),
  'savings': CategoryMeta(
    title: 'Savings',
    description:
        'Flexible and term savings options for households, children, and longer-term goals.',
    icon: Icons.savings_outlined,
    accent: AppColors.accent,
  ),
  'group_account': CategoryMeta(
    title: 'Group & Community Banking',
    description:
        'Community, association, youth, and solidarity-group banking products.',
    icon: Icons.groups_2_outlined,
    accent: AppColors.orange,
  ),
  'group_loan': CategoryMeta(
    title: 'Group Loans',
    description:
        'Community-banking loan products for organized groups and village savings associations.',
    icon: Icons.diversity_3_outlined,
    accent: AppColors.orange,
  ),
  'business_loan': CategoryMeta(
    title: 'Borrowing & Credit',
    description:
        'Personal, SME, asset-finance, mortgage, and working-capital borrowing paths.',
    icon: Icons.storefront_outlined,
    accent: AppColors.red,
  ),
  'agri': CategoryMeta(
    title: 'Agricultural Finance',
    description:
        'Seasonal and value-chain finance across coffee, maize, rice, and Irish potato products.',
    icon: Icons.agriculture_outlined,
    accent: AppColors.whatsapp,
  ),
  'support': CategoryMeta(
    title: 'Support & Onboarding',
    description:
        'Official channels, locations, and contact points for opening or managing services.',
    icon: Icons.support_agent_rounded,
    accent: AppColors.whatsapp,
  ),
};

// ═════════════════════════════════════════════════════════════════════════════
// PARTNER CONFIGS
// ═════════════════════════════════════════════════════════════════════════════

const bankPartnerConfigs = <String, BankPartnerConfig>{
  'urwego': BankPartnerConfig(
    sourceTitle: 'Official Urwego content',
    sourceDescription:
        'This page is backed by Supabase partner data refreshed from Urwego Finance official products, contact, about, and locations pages.',
    defaultDescription:
        'Urwego Finance provides digital banking, savings, credit, transfers, and support channels for households, groups, and small businesses in Rwanda.',
    heroTags: [
      BankHeroTagData(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Accounts & Savings',
      ),
      BankHeroTagData(
        icon: Icons.trending_up_rounded,
        label: 'Group & SME Credit',
      ),
      BankHeroTagData(
        icon: Icons.phone_android_rounded,
        label: 'mHose + Internet Banking',
      ),
    ],
    quickActions: [
      BankQuickActionData(
        icon: Icons.public_rounded,
        title: 'Products',
        subtitle: 'Official products and services',
        action: 'web:$urwegoProductsUrl',
      ),
      BankQuickActionData(
        icon: Icons.laptop_mac_rounded,
        title: 'Internet Banking',
        subtitle: 'Open the online banking portal',
        action: 'web:$urwegoInternetBankingUrl',
      ),
      BankQuickActionData(
        icon: Icons.phone_in_talk_rounded,
        title: 'Call Urwego',
        subtitle: 'Hotline $urwegoHotline',
        action: 'tel:$urwegoPhone',
      ),
      BankQuickActionData(
        icon: Icons.location_on_outlined,
        title: 'Locations',
        subtitle: 'Branches and mHose agents',
        action: 'web:$urwegoLocationsUrl',
      ),
    ],
    supportHeading: 'Need help choosing a service?',
    supportDescription:
        'Use Urwego Finance official contact points for onboarding, product questions, and branch support.',
    supportItems: [
      BankSupportItemData(
        icon: Icons.phone_outlined,
        label: 'Phone',
        value: '5151 / +250 788 173 100',
      ),
      BankSupportItemData(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'WhatsApp',
        value: '+250 785 083 323',
      ),
      BankSupportItemData(
        icon: Icons.alternate_email_rounded,
        label: 'Email',
        value: urwegoSupportEmail,
      ),
      BankSupportItemData(
        icon: Icons.place_outlined,
        label: 'Head office',
        value: 'CHIC Building, Kicukiro, Kigali',
      ),
    ],
    supportButtons: [
      BankSupportButtonData(
        label: 'Chat on WhatsApp',
        action: 'whatsapp:$urwegoWhatsApp',
      ),
      BankSupportButtonData(
        label: 'Email Urwego',
        action: 'mailto:$urwegoSupportEmail',
      ),
    ],
  ),
  'equity': BankPartnerConfig(
    sourceTitle: 'Official Equity Rwanda content',
    sourceDescription:
        'This page is backed by Supabase partner data refreshed from Equity Bank Rwanda official home, account, payments, savings, borrowing, and contact pages.',
    defaultDescription:
        'Equity Bank Rwanda offers personal, SME, corporate, group, and community banking, plus digital channels, savings, payments, and borrowing services in Rwanda.',
    heroTags: [
      BankHeroTagData(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Accounts & Payments',
      ),
      BankHeroTagData(icon: Icons.savings_outlined, label: 'Save & Borrow'),
      BankHeroTagData(
        icon: Icons.phone_android_rounded,
        label: 'Equity Mobile + EazzyBiz',
      ),
    ],
    quickActions: [
      BankQuickActionData(
        icon: Icons.person_add_alt_1_rounded,
        title: 'Open Account',
        subtitle: 'Personal, SME, group, community',
        action: 'web:$equityOpenAccountUrl',
      ),
      BankQuickActionData(
        icon: Icons.swap_horiz_rounded,
        title: 'Pay & Send',
        subtitle: 'Transfers and payment services',
        action: 'web:$equityPayAndSendMoneyUrl',
      ),
      BankQuickActionData(
        icon: Icons.savings_outlined,
        title: 'Save & Invest',
        subtitle: 'Savings and deposit products',
        action: 'web:$equitySaveAndInvestUrl',
      ),
      BankQuickActionData(
        icon: Icons.support_agent_rounded,
        title: 'Talk to Us',
        subtitle: 'Customer care and support',
        action: 'web:$equityTalkToUsUrl',
      ),
    ],
    supportHeading: 'Need Equity Rwanda support?',
    supportDescription:
        'Use Equity Bank Rwanda official contact points for account opening, digital banking help, payments, savings, and borrowing support.',
    supportItems: [
      BankSupportItemData(
        icon: Icons.phone_outlined,
        label: 'Customer care',
        value: '$equityHotline / +250 737 360 000',
      ),
      BankSupportItemData(
        icon: Icons.alternate_email_rounded,
        label: 'Email',
        value: equitySupportEmail,
      ),
      BankSupportItemData(
        icon: Icons.schedule_outlined,
        label: 'Service hours',
        value: 'Weekdays 8:00-18:00 · Weekends 9:00-13:00',
      ),
      BankSupportItemData(
        icon: Icons.public_rounded,
        label: 'Website',
        value: equityHomeUrl,
      ),
    ],
    supportButtons: [
      BankSupportButtonData(label: 'Call Equity', action: 'tel:$equityPhone'),
      BankSupportButtonData(
        label: 'Email Equity',
        action: 'mailto:$equitySupportEmail',
      ),
    ],
  ),
};

// ═════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═════════════════════════════════════════════════════════════════════════════

BankPartnerConfig bankConfigForSlug(String slug) {
  return bankPartnerConfigs[slug] ?? bankPartnerConfigs['urwego']!;
}

String normalizeBankCategory(String rawCategory) {
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

List<MapEntry<String, List<PartnerService>>> groupBankServices(
  List<PartnerService> services,
) {
  final buckets = <String, List<PartnerService>>{};
  for (final service in services) {
    final category = normalizeBankCategory(service.category);
    buckets.putIfAbsent(category, () => <PartnerService>[]).add(service);
  }

  final grouped = <MapEntry<String, List<PartnerService>>>[];
  for (final category in bankCategoryOrder) {
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

Future<void> launchExternalUri(
  BuildContext context,
  Uri uri, {
  String unavailableMessage = 'This action is not available on this device.',
  String failureMessage = 'Could not open this action right now.',
}) async {
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      CoolToast.error(context, unavailableMessage);
    }
  } catch (_) {
    if (context.mounted) {
      CoolToast.error(context, failureMessage);
    }
  }
}

Future<void> launchPartnerAction(
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
        CoolToast.info(
          context,
          'No WhatsApp channel is configured for ${partner.name}.',
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
    await launchExternalUri(
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
    await launchExternalUri(
      context,
      Uri.parse(url),
      unavailableMessage: 'Could not open the official website.',
      failureMessage: 'Could not launch ${partner.name} website right now.',
    );
    return;
  }

  if (normalizedAction.startsWith('tel:')) {
    await launchExternalUri(
      context,
      Uri.parse(normalizedAction),
      unavailableMessage: 'Could not open the dialer.',
      failureMessage: 'Could not call ${partner.name} right now.',
    );
    return;
  }

  if (normalizedAction.startsWith('mailto:')) {
    await launchExternalUri(
      context,
      Uri.parse(normalizedAction),
      unavailableMessage: 'No mail app is available on this device.',
      failureMessage: 'Could not open the email app right now.',
    );
  }
}
