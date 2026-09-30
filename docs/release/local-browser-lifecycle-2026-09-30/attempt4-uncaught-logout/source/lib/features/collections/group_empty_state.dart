import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class MissingGroupStateScreen extends StatelessWidget {
  const MissingGroupStateScreen({this.title = 'Group unavailable', super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: title,
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: 'Open groups',
            icon: CollectIcons.collections,
            onPressed: () => context.go('/groups'),
            expand: true,
          ),
          CollectButton(
            label: 'Edit profile',
            icon: CollectIcons.profile,
            onPressed: () => context.go('/settings/profile'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: const [
        MinimalStatePanel(
          icon: CollectIcons.collectionsOutline,
          title: 'Group is not available.',
          message:
              'The group may not be joined on this device, the link may have expired, or the group may have been removed.',
          tone: CollectStatusTone.warning,
        ),
      ],
    );
  }
}

class ArchivedGroupStateScreen extends StatelessWidget {
  const ArchivedGroupStateScreen({
    required this.collectionId,
    required this.groupTitle,
    super.key,
  });

  final String collectionId;
  final String groupTitle;

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Group archived',
      subtitle: groupTitle,
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: 'Open ledger',
            icon: CollectIcons.ledger,
            onPressed: () => context.go('/groups/$collectionId/ledger'),
            expand: true,
          ),
          CollectButton(
            label: 'Open active groups',
            icon: CollectIcons.collections,
            onPressed: () => context.go('/groups'),
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
      children: const [
        MinimalStatePanel(
          icon: Icons.archive_rounded,
          title: 'This group is archived.',
          message:
              'New contributions, invitations, sharing, and profile changes are off. Existing confirmed ledger records remain available.',
          tone: CollectStatusTone.warning,
        ),
      ],
    );
  }
}
