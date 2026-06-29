part of 'public_content.dart';

class LandingStepData {
  const LandingStepData({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
}

String publicInfographicTitle(String path) {
  switch (path) {
    case '/group-savings':
      return 'How Collect works';
    case '/diaspora':
      return 'Diaspora savings pathway';
    case '/insurance':
      return 'How insurance support works';
    case '/craas':
      return 'From inquiry to support file';
    case '/community-groups':
      return 'What the app enables';
    case '/our-partners':
      return 'Bank growth workflow';
    case '/account-deletion':
      return 'Customer deletion request';
    case '/data-deletion':
      return 'Data deletion request';
  }
  return 'Collect workflow';
}

String publicInfographicBody(String path) {
  switch (path) {
    case '/group-savings':
      return 'Create the group, invite members, contribute with proof, build history, and connect to partners.';
    case '/diaspora':
      return 'Save across borders with clearer rules and records.';
    case '/insurance':
      return 'Show terms, collect premiums flexibly, provide proof, and support claim notification.';
    case '/craas':
      return 'Move from inquiry to a complete, indexed application file.';
    case '/community-groups':
      return 'Give leaders and members cleaner records without changing group governance.';
    case '/our-partners':
      return 'Convert existing savings discipline into formal deposits, reliable data and bankable credit relationships.';
    case '/account-deletion':
      return 'Request deletion in app or through IKANISA support.';
    case '/data-deletion':
      return 'Ask support to delete or correct data that is no longer needed.';
  }
  return 'A clear workflow that shows how Collect turns activity into usable records.';
}

Color publicInfographicBackground(String path) {
  switch (path) {
    case '/insurance':
      return CollectColors.publicSoftDanger;
    case '/craas':
      return CollectColors.publicSoftInfo;
    case '/diaspora':
      return CollectColors.publicMintSurface;
    case '/our-partners':
      return CollectColors.publicSoftNeutral;
    default:
      return CollectColors.publicWhite;
  }
}

List<LandingStepData> publicInfographicSteps(String path) {
  switch (path) {
    case '/group-savings':
      return const [
        LandingStepData(
          icon: Icons.group_add_outlined,
          title: 'Create the group',
          body: 'Define purpose, leadership, rules and contribution schedule.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.dialpad_outlined,
          title: 'Invite members',
          body:
              'Onboard members through the app or supported assisted channels.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.sms_outlined,
          title: 'Contribute and get proof',
          body:
              'Members save through the app, mobile money, or USSD and receive confirmation.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Build history',
          body: 'Contribution consistency becomes a verified record.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.account_balance_outlined,
          title: 'Connect to partners',
          body: 'Eligible groups may access partner-led finance.',
          color: CollectColors.brandMintGreen,
        ),
      ];
    case '/diaspora':
      return const [
        LandingStepData(
          icon: Icons.public_outlined,
          title: 'Form the group',
          body: 'Members agree roles, rules and saving objectives.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Track contributions',
          body: 'Savings history is organized into readable group records.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.inventory_2_outlined,
          title: 'Prepare information',
          body: 'Members keep the records needed for discussion and support.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.location_on_outlined,
          title: 'Invest at home',
          body: 'Use the loan to invest in property or a business in Rwanda.',
          color: CollectColors.brandDustyRose,
        ),
      ];
    case '/insurance':
      return const [
        LandingStepData(
          icon: Icons.support_agent_outlined,
          title: 'Display terms',
          body: 'Show product terms, exclusions, price and insurer.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Collect premium',
          body: 'Collect daily or through a flexible schedule.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.verified_user_outlined,
          title: 'Provide proof',
          body: 'Member receives digital proof of cover.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.chat_bubble_outline,
          title: 'Support claims',
          body: 'Collect supports notification; insurer decides claims.',
          color: CollectColors.brandPeriwinkle,
        ),
      ];
    case '/craas':
      return const [
        LandingStepData(
          icon: Icons.chat_bubble_outline,
          title: 'Inquiry',
          body: 'Understand the customer need.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.inventory_2_outlined,
          title: 'Requirement mapping',
          body: 'Match the request to bank and product requirements.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.rule_outlined,
          title: 'Document preparation',
          body: 'Guide preparation of required documents and services.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.account_balance_outlined,
          title: 'Bank-ready package',
          body: 'Index the completed application for bank review.',
          color: CollectColors.brandDustyRose,
        ),
      ];
    case '/community-groups':
      return const [
        LandingStepData(
          icon: Icons.home_outlined,
          title: 'Lead',
          body: 'Create groups, set rules, assign roles and track activity.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.groups_outlined,
          title: 'Contribute',
          body: 'Members contribute and receive proof.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.settings_outlined,
          title: 'Follow progress',
          body: 'Members view personal and group progress.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.support_agent_outlined,
          title: 'Build history',
          body: 'Verified contribution records support next steps.',
          color: CollectColors.brandPeriwinkle,
        ),
      ];
    case '/our-partners':
      return const [
        LandingStepData(
          icon: Icons.savings_outlined,
          title: 'Mobilise deposits',
          body:
              'Bring daily and group savings into clearer bank-linked records.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Build data',
          body:
              'Turn contribution history into repayment and credit-readiness signals.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.rule_outlined,
          title: 'Prepare credit',
          body: 'Package MSME and group-backed files for formal bank review.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.account_balance_outlined,
          title: 'Grow relationships',
          body:
              'Support deposits, lending and diaspora banking under bank approval.',
          color: CollectColors.brandDustyRose,
        ),
      ];
  }
  return const [];
}
