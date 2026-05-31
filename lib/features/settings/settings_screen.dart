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
                onTap: () => context.go('/profile/setup'),
              ),
              const CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS access',
                subtitle: 'Android SMS access for automated MoMo parsing.',
              ),
              const CollectListTile(
                leading: CollectIcons.lock,
                title: 'Privacy boundary',
                subtitle:
                    'Raw SMS, phone numbers, and receiver data stay restricted.',
                trailing: CollectStatusChip(
                  label: 'Protected',
                  tone: CollectStatusTone.privacy,
                ),
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
