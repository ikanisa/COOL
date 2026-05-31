import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Settings',
      subtitle: 'Profile, MoMo number, SMS access, and trust settings.',
      children: [
        const InsightCard(
          title: 'Collect settings',
          message:
              'Your MoMo number and 6-digit Collect ID stay in your profile and sync into group flows.',
          icon: CollectIcons.shield,
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile and MoMo number',
                subtitle: 'Collect ID and default group receiver number.',
                onTap: () => context.go('/settings/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.check,
                title: 'Profile readiness',
                subtitle: 'Collect ID, MoMo, and group creation readiness.',
                onTap: () => context.go('/settings/readiness'),
              ),
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS access',
                subtitle: 'Android SMS access for automated MoMo parsing.',
                onTap: () => context.go('/permissions/sms'),
              ),
              CollectListTile(
                leading: CollectIcons.tune,
                title: 'Device permissions',
                subtitle: 'Notification and SMS readiness.',
                onTap: () => context.go('/permissions/device'),
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Privacy boundary',
                subtitle:
                    'Raw SMS, phone numbers, and receiver data stay restricted.',
                onTap: () => context.go('/settings/privacy'),
                trailing: const CollectStatusChip(
                  label: 'Protected',
                  tone: CollectStatusTone.privacy,
                ),
              ),
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Account and session',
                subtitle: 'Sign out or submit account requests.',
                onTap: () => context.go('/settings/account'),
              ),
              CollectListTile(
                leading: CollectIcons.support,
                title: 'Help and support',
                subtitle: 'Send a support request.',
                onTap: () => context.go('/settings/help'),
              ),
              CollectListTile(
                leading: CollectIcons.info,
                title: 'Terms',
                subtitle: 'Collect product terms.',
                onTap: () => context.go('/settings/legal/terms'),
              ),
              CollectListTile(
                leading: CollectIcons.privacy,
                title: 'Privacy policy',
                subtitle: 'Data and evidence handling.',
                onTap: () => context.go('/settings/legal/privacy'),
              ),
              if (kDebugMode)
                CollectListTile(
                  leading: CollectIcons.palette,
                  title: 'Design system',
                  subtitle: 'Debug component catalog for Collect UI QA.',
                  onTap: () => context.go('/dev/design-system'),
                ),
            ],
          ),
        ),
        const InsightCard(
          title: 'Automated by design',
          message:
              'Contributions are matched from payment intents and MoMo SMS parsing.',
          icon: CollectIcons.tips,
          tone: CollectStatusTone.success,
        ),
      ],
    );
  }
}
