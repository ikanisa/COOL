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
      return 'Group savings journey';
    case '/diaspora':
      return 'Diaspora savings pathway';
    case '/insurance':
      return 'Insurance support workflow';
    case '/craas':
      return 'From inquiry to support file';
    case '/community-groups':
      return 'What the app enables for a group';
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
      return 'Start together. Save together. Build a record together.';
    case '/diaspora':
      return 'Save across borders with clearer rules and records.';
    case '/insurance':
      return 'Keep customer records clearer when an approved provider is involved.';
    case '/craas':
      return 'Turn customer activity into a cleaner readiness file.';
    case '/community-groups':
      return 'Give trusted groups a simple mobile operating layer.';
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
          title: 'Start the group',
          body:
              'Set up a savings group with clear members, purpose and contribution rhythm.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.dialpad_outlined,
          title: 'Invite members',
          body:
              'Share a link or QR code through the channels members already use.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.sms_outlined,
          title: 'Track saving',
          body:
              'Members contribute and the group follows progress from one record.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Use the record',
          body: 'Turn contribution history into statements and support files.',
          color: CollectColors.brandOrangeRed,
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
          title: 'Discuss next steps',
          body:
              'Any financial-service decision remains with the relevant provider.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/insurance':
      return const [
        LandingStepData(
          icon: Icons.support_agent_outlined,
          title: 'Customer request',
          body: 'Understand the insurance-related question.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.receipt_long_outlined,
          title: 'Record support',
          body: 'Organize relevant customer and group records.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.verified_user_outlined,
          title: 'Provider review',
          body: 'Approved providers review under their own rules.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.chat_bubble_outline,
          title: 'Support follow-up',
          body: 'IKANISA support helps customers understand next steps.',
          color: CollectColors.brandOrangeRed,
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
          title: 'File support',
          body: 'Organize records and missing items.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.rule_outlined,
          title: 'Readiness notes',
          body: 'Prepare a clear customer summary.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.account_balance_outlined,
          title: 'Provider review',
          body: 'Credit decisions remain with the financial provider.',
          color: CollectColors.brandOrangeRed,
        ),
      ];
    case '/community-groups':
      return const [
        LandingStepData(
          icon: Icons.home_outlined,
          title: 'Join',
          body: 'Enter the group from a link or QR code.',
          color: CollectColors.brandPeriwinkle,
        ),
        LandingStepData(
          icon: Icons.groups_outlined,
          title: 'Save',
          body: 'Contribute and follow the group record.',
          color: CollectColors.brandMintGreen,
        ),
        LandingStepData(
          icon: Icons.settings_outlined,
          title: 'Track',
          body: 'See member activity and progress.',
          color: CollectColors.brandDustyRose,
        ),
        LandingStepData(
          icon: Icons.support_agent_outlined,
          title: 'Support',
          body: 'Get help without exposing private data.',
          color: CollectColors.brandOrangeRed,
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
          color: CollectColors.brandOrangeRed,
        ),
      ];
  }
  return const [];
}
