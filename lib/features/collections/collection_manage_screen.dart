import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class CollectionManageScreen extends ConsumerWidget {
  const CollectionManageScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.collectionById(collectionId);

    return ScreenScaffold(
      title: 'Manage group',
      subtitle: collection.title,
      children: [
        CollectCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CollectListTile(
                leading: CollectIcons.dashboard,
                title: 'Owner',
                subtitle: 'Health, receiver, members.',
                onTap: () => context.go('/groups/$collectionId/owner'),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Share',
                subtitle: 'Link, QR, chat.',
                onTap: () => context.go('/groups/$collectionId/share'),
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger',
                subtitle: 'Activity.',
                onTap: () => context.go('/groups/$collectionId/ledger'),
              ),
              CollectListTile(
                leading: CollectIcons.momo,
                title: 'Receiver',
                subtitle: 'Owner only.',
                onTap: () => context.go('/groups/$collectionId/owner/receiver'),
              ),
              CollectListTile(
                leading: CollectIcons.people,
                title: 'Members',
                subtitle: 'Active.',
                onTap: () => context.go('/groups/$collectionId/members'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
