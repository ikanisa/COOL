import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money_format.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';
import 'group_share_service.dart';

class CollectionManageScreen extends ConsumerWidget {
  const CollectionManageScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final summary = repo.summaryFor(collectionId);
    final profile = state.currentProfile;
    final isOwner = profile != null && collection.creatorUserId == profile.id;

    if (!isOwner) {
      return ScreenScaffold(
        title: 'Group settings',
        subtitle: collection.title,
        children: [
          const MinimalStatePanel(
            icon: CollectIcons.lock,
            title: 'Owner only.',
            message:
                'Group settings are visible only to the group owner. Members can view activity, members, QR, and contribution screens.',
            tone: CollectStatusTone.privacy,
          ),
          CollectButton(
            label: 'Open group',
            icon: CollectIcons.collections,
            onPressed: () => context.go('/groups/$collectionId'),
            expand: true,
          ),
        ],
      );
    }

    return ScreenScaffold(
      title: 'Group settings',
      subtitle: collection.title,
      children: [
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          child: Column(
            children: [
              CollectListTile(
                leading: CollectIcons.info,
                title: 'Group profile',
                subtitle: 'Name, image, visibility, recurrence, receiver.',
                onTap: () => context.go('/groups/$collectionId/profile'),
              ),
              CollectListTile(
                leading: CollectIcons.qr,
                title: 'Group QR',
                subtitle: 'Show, share, or save the QR image.',
                onTap: () => context.go('/groups/$collectionId/share'),
              ),
              CollectListTile(
                leading: CollectIcons.share,
                title: 'Share group',
                subtitle: 'Native share invite link.',
                onTap: () => shareGroupDeepLink(
                  context: context,
                  ref: ref,
                  collection: collection,
                ),
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger',
                subtitle: formatRwf(summary.amountRaisedRwf),
                onTap: () => context.go('/groups/$collectionId/ledger'),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Members',
                subtitle: '${summary.supporterCount}',
                onTap: () => context.go('/groups/$collectionId/members'),
              ),
              const CollectListTile(
                leading: CollectIcons.support,
                title: 'Support',
                onTap: openCollectWhatsAppSupport,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
