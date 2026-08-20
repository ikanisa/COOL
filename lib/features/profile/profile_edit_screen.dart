import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ProfileEditScreen extends ConsumerWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    return ScreenScaffold(
      title: 'Profile',
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: profile == null ? 'Sign in' : 'Back to settings',
            icon: profile == null ? CollectIcons.profile : CollectIcons.chevron,
            onPressed: () =>
                context.go(profile == null ? '/auth' : '/settings'),
            expand: true,
          ),
        ],
      ),
      children: [
        const CollectPlainPageHeader(title: 'Profile'),
        if (profile == null)
          const MinimalStatePanel(
            icon: CollectIcons.lock,
            title: 'Sign in first',
            message:
                'Collect creates your private 6-digit ID after WhatsApp verification.',
            tone: CollectStatusTone.warning,
          )
        else ...[
          const InfoSecurityBanner(
            title: 'Payment details are centrally governed',
            message:
                'Your profile does not store a payment receiver. Every contribution uses the approved EUR bank beneficiary shown in Settings.',
            tone: CollectStatusTone.privacy,
          ),
          CollectIdDisplay(
            publicId: profile.publicId,
            onCopy: () => copyToClipboard(
              context,
              profile.publicId,
              message: 'Collect ID copied.',
            ),
          ),
          CollectCard(
            child: Column(
              children: [
                CollectListTile(
                  leading: CollectIcons.bank,
                  title: 'Bank transfer details',
                  subtitle: 'Review the approved beneficiary and IBAN.',
                  onTap: () => context.go('/settings/bank-transfer'),
                ),
                CollectListTile(
                  leading: CollectIcons.lock,
                  title: 'Account and session',
                  subtitle: 'Review session controls or sign out.',
                  onTap: () => context.go('/settings/account'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
