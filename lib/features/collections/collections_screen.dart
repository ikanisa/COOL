import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/widgets/collect_components.dart';
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
      return ScreenScaffold(
        title: 'Groups',
        children: [
          EmptyIllustrationState(
            icon: CollectIcons.collectionsOutline,
            title: 'No groups yet',
            message:
                'Create an Android owner group, or join one from a Collect link, code, or QR.',
            action: CollectButton(
              label: 'Join group',
              icon: CollectIcons.qr,
              onPressed: () => context.go('/groups/join'),
            ),
          ),
          CollectButton(
            label: 'Create group',
            icon: CollectIcons.add,
            onPressed: () => openGroupCreation(context),
            expand: true,
          ),
        ],
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
        IconButton(
          tooltip: 'Join group',
          onPressed: () => context.go('/groups/join'),
          icon: const Icon(CollectIcons.qr),
        ),
      ],
      children: [
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          accentColor: context.collectColors.actionCrimson,
          padding: CollectSpacing.cardPaddingComfortable,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.collectColors.actionCrimson.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: CollectRadius.panelBorder,
                ),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(CollectIcons.qr),
                ),
              ),
              CollectSpacing.gapW16,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Group links are safe to share',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    CollectSpacing.gap4,
                    Text(
                      'Join links and QR codes connect members without exposing receiver MoMo details.',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
            variant: GroupCardVariant.owned,
          ),
      ],
    );
  }
}
