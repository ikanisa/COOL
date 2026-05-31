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
        title: 'No groups yet',
        message:
            'Create a group, confirm the receiver MoMo number, then share it by link or QR code.',
        action: CollectButton(
          label: 'Create group',
          icon: CollectIcons.add,
          onPressed: () => openGroupCreation(context),
        ),
      );
    }
    return ScreenScaffold(
      title: 'Groups',
      subtitle: 'Shared MoMo groups with SMS-matched contributions.',
      actions: [
        IconButton.filled(
          tooltip: 'New group',
          onPressed: () => openGroupCreation(context),
          icon: const Icon(CollectIcons.add),
        ),
      ],
      children: [
        const SecurityNotice(
          title: 'Automated allocation',
          message:
              'Each contribution creates a payment intent. MoMo SMS confirms and allocates it automatically.',
        ),
        Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            CollectStatusChip(
              label: '${collections.length} active',
              tone: CollectStatusTone.info,
            ),
            const CollectStatusChip(
              label: 'SMS parsing',
              tone: CollectStatusTone.privacy,
            ),
          ],
        ),
        for (final collection in collections)
          GroupCard(
            collection: collection,
            summary:
                summaries[collection.id] ??
                const CollectionSummary(amountRaisedRwf: 0, supporterCount: 0),
            onTap: () => context.go('/groups/${collection.id}'),
            primaryAction: CollectButton(
              label: 'Open group',
              icon: CollectIcons.arrowForward,
              onPressed: () => context.go('/groups/${collection.id}'),
              expand: true,
            ),
          ),
      ],
    );
  }
}
