import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collection_card.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/screen_scaffold.dart';

class PublicDirectoryScreen extends ConsumerWidget {
  const PublicDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collections = repo.publicCollections;
    if (collections.isEmpty) {
      return const EmptyState(
        icon: CollectIcons.publicOutline,
        title: 'No approved public collections',
        message:
            'Public collections appear here only after platform admin approval.',
      );
    }
    return ScreenScaffold(
      title: 'Public directory',
      subtitle:
          'Approved Rwanda collections. Receiver MOMO details stay hidden until contribution.',
      children: [
        const InfoSecurityBanner(
          title: 'Public-safe browsing',
          message:
              'Public cards never expose receiver MOMO numbers, phone numbers, or raw SMS. Details appear only in the contribution step.',
          tone: CollectStatusTone.privacy,
        ),
        for (final collection in collections)
          CollectionCard(
            collection: collection,
            summary: repo.summaryFor(collection.id),
            onTap: () => context.go('/collections/${collection.id}'),
          ),
      ],
    );
  }
}
