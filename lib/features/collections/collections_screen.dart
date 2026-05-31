import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(
      collectRepositoryProvider.select((state) => state.collections),
    );
    final summaries = ref.watch(collectionSummariesProvider);
    if (collections.isEmpty) {
      return EmptyState(
        icon: CollectIcons.collectionsOutline,
        title: 'No groups',
        message: 'Create, confirm, share.',
        action: CollectButton(
          label: 'Create group',
          icon: CollectIcons.add,
          onPressed: () => openGroupCreation(context),
        ),
      );
    }
    return ScreenScaffold(
      title: 'Groups',
      actions: [
        IconButton.filled(
          tooltip: 'New group',
          onPressed: () => openGroupCreation(context),
          icon: const Icon(CollectIcons.add),
        ),
      ],
      children: [
        for (final collection in collections)
          GroupCard(
            collection: collection,
            summary:
                summaries[collection.id] ??
                const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0),
            onTap: () => context.go('/groups/${collection.id}'),
            primaryAction: CollectButton(
              label: 'Open',
              icon: CollectIcons.arrowForward,
              onPressed: () => context.go('/groups/${collection.id}'),
              expand: true,
            ),
          ),
      ],
    );
  }
}
