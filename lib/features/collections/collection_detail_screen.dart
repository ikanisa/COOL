import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';
import 'group_share_service.dart';

part 'collection_detail_actions.dart';
part 'collection_detail_hero.dart';
part 'collection_detail_timeline.dart';

class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    final summary = repo.summaryFor(collectionId);
    final visibleContributions = repo
        .contributionsFor(collectionId)
        .take(8)
        .toList();
    final profile = state.currentProfile;
    final isAdmin = profile != null && collection.creatorUserId == profile.id;

    return ScreenScaffold(
      title: 'Collect',
      subtitle: profile?.publicId,
      showHeader: false,
      bottomAction: isAdmin
          ? null
          : CollectButton(
              label: 'Contribute',
              icon: CollectIcons.donate,
              onPressed: () => context.go('/groups/$collectionId/contribute'),
              expand: true,
            ),
      children: [
        CollectPlainPageHeader(title: collection.title),
        _GroupHero(
          collectionId: collectionId,
          collection: collection,
          summary: summary,
          canManage: isAdmin,
        ),
        _GroupActionStrip(collectionId: collectionId, collection: collection),
        const SectionHeader(title: 'Activity'),
        if (visibleContributions.isEmpty)
          const EmptyIllustrationState(
            icon: CollectIcons.activity,
            title: 'No support yet',
            message:
                'Confirmed contributions will appear after MoMo SMS verification.',
          )
        else
          _ContributionTimeline(contributions: visibleContributions),
      ],
    );
  }
}
