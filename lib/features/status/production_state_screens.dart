import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

export 'access_state_screens.dart';
export 'device_privacy_screens.dart';
export 'account_legal_screens.dart';
export 'group_members_screen.dart';

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

class FreshLinkRequestScreen extends StatefulWidget {
  const FreshLinkRequestScreen({required this.slug, super.key});

  final String slug;

  @override
  State<FreshLinkRequestScreen> createState() => _FreshLinkRequestScreenState();
}

class _FreshLinkRequestScreenState extends State<FreshLinkRequestScreen> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Fresh link',
      children: [
        _StateHero(
          icon: CollectIcons.sync,
          title: _submitted ? 'Request sent.' : 'Request a fresh link.',
          tone: _submitted ? CollectStatusTone.success : CollectStatusTone.info,
        ),
        InfoSecurityBanner(
          title: 'Link safety',
          message: widget.slug.trim().isEmpty
              ? 'Ask the group owner for a new invite without sharing receiver or payment details.'
              : 'Ask the group owner for a new invite to this group without sharing receiver or payment details.',
          tone: CollectStatusTone.privacy,
        ),
        CollectButton(
          label: _submitted ? 'Open groups' : 'Request fresh link',
          icon: _submitted ? CollectIcons.collections : CollectIcons.sync,
          onPressed: _submitted
              ? () => context.go('/groups')
              : () => setState(() => _submitted = true),
          expand: true,
        ),
        CollectButton(
          label: 'Scan QR',
          icon: CollectIcons.qr,
          onPressed: () => context.go('/groups/scan'),
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
