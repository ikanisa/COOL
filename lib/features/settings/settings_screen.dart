import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(
      collectRepositoryProvider.select((state) => state.currentProfile),
    );
    return ScreenScaffold(
      title: 'Settings',
      children: [
        CollectIdCard(publicId: profile?.publicId ?? ''),
        CollectCard(
          padding: CollectSpacing.cardPaddingComfortable,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Profile',
                subtitle: profile == null ? null : '#${profile.publicId}',
                onTap: () => context.go('/settings/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.check,
                title: 'Readiness',
                subtitle: 'Profile and groups.',
                onTap: () => context.go('/settings/readiness'),
              ),
              CollectListTile(
                leading: CollectIcons.sms,
                title: 'SMS access',
                subtitle: 'Android owners.',
                onTap: () => context.go('/permissions/sms'),
              ),
              CollectListTile(
                leading: CollectIcons.tune,
                title: 'Device permissions',
                subtitle: 'Device access.',
                onTap: () => context.go('/permissions/device'),
              ),
              CollectListTile(
                leading: CollectIcons.pending,
                title: 'Notifications',
                subtitle: 'Payment and group updates.',
                onTap: () => context.go('/notifications'),
              ),
              CollectListTile(
                leading: CollectIcons.lock,
                title: 'Privacy',
                subtitle: 'Data controls.',
                onTap: () => context.go('/settings/privacy'),
              ),
              CollectListTile(
                leading: CollectIcons.profile,
                title: 'Account',
                subtitle: 'Session and requests.',
                onTap: () => context.go('/settings/account'),
              ),
              CollectListTile(
                leading: CollectIcons.support,
                title: 'Help',
                subtitle: 'Support request.',
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
                  subtitle: 'UI catalog.',
                  onTap: () => context.go('/dev/design-system'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
