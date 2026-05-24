import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/screen_scaffold.dart';

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
        title: 'No goals yet',
        message:
            'Create a private goal, add a receiver MOMO number, then share it when ready.',
        action: CollectButton(
          label: 'Create collection',
          icon: CollectIcons.add,
          onPressed: () => context.go('/collections/create'),
        ),
      );
    }
    return ScreenScaffold(
      title: 'Goals',
      subtitle: 'Organize collections like money pots.',
      actions: [
        IconButton.filled(
          tooltip: 'New collection',
          onPressed: () => context.go('/collections/create'),
          icon: const Icon(CollectIcons.add),
        ),
      ],
      children: [
        const SecurityNotice(
          title: 'Private by default',
          message:
              'Goals start private. Public listings require admin approval and safe public copy.',
        ),
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            CollectStatusChip(
              label: '${collections.length} active',
              tone: CollectStatusTone.info,
            ),
            CollectStatusChip(
              label:
                  '${collections.where((item) => item.isPublicApproved).length} public',
              tone: CollectStatusTone.success,
            ),
            const CollectStatusChip(
              label: 'MOMO direct',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        for (final collection in collections)
          CollectionGoalCard(
            collection: collection,
            summary:
                summaries[collection.id] ??
                const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0),
            onTap: () => context.go('/collections/${collection.id}'),
            primaryAction: CollectButton(
              label: 'Open goal',
              icon: CollectIcons.arrowForward,
              onPressed: () => context.go('/collections/${collection.id}'),
              expand: true,
            ),
          ),
      ],
    );
  }
}
