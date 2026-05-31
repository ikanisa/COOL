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
                leading: CollectIcons.people,
                title: 'Share group',
                subtitle:
                    'Share by link, QR code, chat app, SMS, or deep link.',
                onTap: () => context.go('/groups/$collectionId/share'),
              ),
              CollectListTile(
                leading: CollectIcons.ledger,
                title: 'Ledger',
                subtitle: 'Confirmed SMS-matched contributions.',
                onTap: () => context.go('/groups/$collectionId/ledger'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
