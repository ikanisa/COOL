import 'package:flutter/material.dart';

class BankPartnerConfig {
  const BankPartnerConfig({
    required this.slug,
    required this.name,
    required this.description,
    required this.quickActions,
  });

  final String slug;
  final String name;
  final String description;
  final List<BankQuickActionData> quickActions;
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

const bankPartnerConfigs = <String, BankPartnerConfig>{
  'urwego': BankPartnerConfig(
    slug: 'urwego',
    name: 'Urwego Finance',
    description: 'Urwego Finance provides digital',
    quickActions: [
      BankQuickActionData(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Open Account',
        subtitle: 
 'Digital onboarding',
        action: 'internal:open_account',
      ),
      BankQuickActionData(
        icon: Icons.people_rounded,
        title: 'Group Savings',
        subtitle: 
 'Digital group wallet',
        action: 'internal:group_savings',
      ),
      BankQuickActionData(
        icon: Icons.monetization_on_rounded,
        title: 'Get Loan',
        subtitle: 
 'Fast credit access',
        action: 'internal:get_loan',
      ),
    ],
  ),
  'equity': BankPartnerConfig(
    slug: 'equity',
    name: 'Equity Bank Rwanda',
    description: 'Equity Bank Rwanda offers',
    quickActions: [
      BankQuickActionData(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Open Account',
        subtitle: 
 'Digital onboarding',
        action: 'internal:open_account',
      ),
      BankQuickActionData(
        icon: Icons.people_rounded,
        title: 'Group Savings',
        subtitle: 
 'Digital group wallet',
        action: 'internal:group_savings',
      ),
      BankQuickActionData(
        icon: Icons.monetization_on_rounded,
        title: 'Get Loan',
        subtitle: 
 'Fast credit access',
        action: 'internal:get_loan',
      ),
    ],
  ),
};

BankPartnerConfig bankConfigForSlug(String slug) {
  return bankPartnerConfigs[slug] ?? bankPartnerConfigs['urwego']!;
}
