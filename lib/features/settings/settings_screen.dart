import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
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
      showHeader: false,
      persistentPill: CollectTopChrome(
        avatarLabel: profile?.publicId,
        searchLabel: 'Settings',
        showSearch: false,
        onAvatarTap: () => context.go('/settings/profile'),
        actions: [
          CollectTopChromeAction(
            icon: CollectIcons.profile,
            tooltip: 'Profile',
            onPressed: () => context.go('/settings/profile'),
          ),
          CollectTopChromeAction(
            icon: CollectIcons.pending,
            tooltip: 'Notifications',
            onPressed: () => context.go('/notifications'),
          ),
        ],
      ),
      children: [
        CollectIdCard(publicId: profile?.publicId ?? ''),
        _SettingsCluster(
          tone: CollectStatusTone.privacy,
          children: [
            CollectListTile(
              leading: CollectIcons.tune,
              title: 'Device permissions',
              subtitle: 'SMS and notifications.',
              onTap: () => context.go('/permissions/device'),
            ),
            CollectListTile(
              leading: CollectIcons.pending,
              title: 'Notifications',
              subtitle: 'Payment and group alerts.',
              onTap: () => context.go('/notifications'),
            ),
          ],
        ),
        _SettingsCluster(
          tone: CollectStatusTone.info,
          children: [
            CollectListTile(
              leading: CollectIcons.profile,
              title: 'Account',
              subtitle: 'Profile, session, and requests.',
              onTap: () => context.go('/settings/account'),
            ),
            CollectListTile(
              leading: CollectIcons.check,
              title: 'Readiness',
              subtitle: 'Profile and groups.',
              onTap: () => context.go('/settings/readiness'),
            ),
          ],
        ),
        _SettingsCluster(
          tone: CollectStatusTone.success,
          children: [
            const CollectListTile(
              leading: CollectIcons.support,
              title: 'Help',
              subtitle: 'WhatsApp support.',
              onTap: openCollectWhatsAppSupport,
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
      ],
    );
  }
}

class _SettingsCluster extends StatelessWidget {
  const _SettingsCluster({required this.children, required this.tone});

  final List<Widget> children;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = colors.statusForeground(tone);
    return CollectCard(
      emphasis: CollectCardEmphasis.tonal,
      accentColor: accent,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
