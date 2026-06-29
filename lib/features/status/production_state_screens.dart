import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

export 'onboarding_status_screens.dart';
export 'access_state_screens.dart';
export 'payment_status_screens.dart';
export 'device_privacy_screens.dart';
export 'account_legal_screens.dart';
export 'group_members_screen.dart';

class GroupCreatedSuccessScreen extends ConsumerWidget {
  const GroupCreatedSuccessScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _safeCollection(ref, collectionId);
    return ScreenScaffold(
      title: 'Group created',
      children: [
        CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StateHero(
                icon: CollectIcons.check,
                title: collection?.title ?? 'Group created.',
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Open group',
                icon: CollectIcons.collections,
                onPressed: () => context.go('/groups/$collectionId'),
                expand: true,
              ),
              CollectButton(
                label: 'Share group',
                icon: CollectIcons.share,
                variant: CollectButtonVariant.secondary,
                onPressed: () => context.go('/groups/$collectionId/share'),
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class JoinGroupConfirmationScreen extends ConsumerWidget {
  const JoinGroupConfirmationScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = _safeCollection(ref, collectionId);
    return ScreenScaffold(
      title: 'Group joined',
      children: [
        CollectBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StateHero(
                icon: CollectIcons.check,
                title: collection?.title ?? 'Joined.',
                tone: CollectStatusTone.success,
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Open group',
                icon: CollectIcons.collections,
                onPressed: () => context.go('/groups/$collectionId'),
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SharedLinkProblemScreen extends StatelessWidget {
  const SharedLinkProblemScreen({required this.expired, super.key});

  final bool expired;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: expired ? 'Link expired' : 'Link unavailable',
      children: [
        _StateHero(
          icon: CollectIcons.error,
          title: expired ? 'Link expired.' : 'Link unavailable.',
          tone: CollectStatusTone.danger,
        ),
        const InfoSecurityBanner(
          title: 'Receiver privacy',
          message:
              'Invalid and expired public links never reveal receiver information. Receiver setup stays inside the contribution review step.',
          tone: CollectStatusTone.privacy,
        ),
        CollectButton(
          label: 'Scan QR',
          icon: CollectIcons.qr,
          onPressed: () => context.go('/groups/scan'),
          expand: true,
        ),
        CollectButton(
          label: 'Open groups',
          icon: CollectIcons.collections,
          onPressed: () => context.go('/groups'),
          variant: CollectButtonVariant.secondary,
          expand: true,
        ),
        if (expired)
          CollectButton(
            label: 'Request fresh link',
            icon: CollectIcons.sync,
            onPressed: () => context.go('/share/expired/request'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        const CollectButton(
          label: 'Get help',
          icon: CollectIcons.support,
          onPressed: openCollectWhatsAppSupport,
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
  }
}

class _StateHero extends StatelessWidget {
  const _StateHero({
    required this.icon,
    required this.title,
    this.tone = CollectStatusTone.info,
  });

  final IconData icon;
  final String title;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CollectStatusChip(label: title, tone: tone, icon: icon),
          CollectSpacing.gap20,
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ],
      ),
    );
  }
}

CollectCollection? _safeCollection(WidgetRef ref, String collectionId) {
  return ref
      .read(collectRepositoryProvider.notifier)
      .maybeCollectionById(collectionId);
}
