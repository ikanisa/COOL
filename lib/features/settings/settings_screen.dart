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
      title: 'Control',
      subtitle: 'Profile, privacy, receiver mode, and trust settings.',
      children: [
        const InsightCard(
          title: 'Collect controls',
          message:
              'Your money stays with receivers. Your evidence stays private.',
          icon: CollectIcons.shield,
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile and MOMO number',
                subtitle:
                    'Public ID, display name, anonymity, receiver number.',
                onTap: () => context.go('/profile/setup'),
              ),
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'Receiver mode',
                subtitle: 'Consent, manual SMS paste, verified sync.',
                onTap: () => context.go('/receiver'),
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
          title: 'Clear by design',
          message:
              'Every payment action should say who receives money, what Collect verifies, and what stays private.',
          icon: CollectIcons.tips,
          tone: CollectStatusTone.success,
        ),
      ],
    );
  }
}
