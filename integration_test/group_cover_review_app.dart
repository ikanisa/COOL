// Explicit local QA entry point; excluded from production imports.
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/collections/collection_create_screen.dart';
import 'package:collect_app/features/collections/group_profile_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:collect_app/shared/widgets/collect_group_cards.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  if (!kDebugMode ||
      !const bool.fromEnvironment('COLLECT_GROUP_COVER_QA') ||
      (!kIsWeb && appFlavor != 'dev')) {
    throw StateError('This entry point requires explicit local photo QA.');
  }
  final repository = CollectRepository.fixture(
    initialState: CollectState(
      currentProfile: const CollectProfile(
        id: 'cover-qa-owner',
        publicId: '123456',
        whatsappPhone: '+250788123456',
        countryCode: 'RW',
        currencyCode: 'RWF',
        momoProvider: 'mtn_momo',
        momoNumber: '0788123456',
      ),
      collections: [
        CollectCollection(
          id: 'qa-private-group',
          slug: 'qa-private-group',
          creatorUserId: 'cover-qa-owner',
          title: 'QA wedding group',
          description: 'Local fixture only',
          collectionType: CollectionType.wedding,
          receiverMomoNumber: '0788123456',
          receiverDisplayLabel: 'QA receiver',
          receiverNetwork: 'mtn_momo',
          isPublic: false,
          createdAt: DateTime(2026, 9, 6),
        ),
      ],
      paymentIntents: const [],
      contributions: const [],
    ),
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, state) => const _ReviewHome()),
      GoRoute(path: '/home', builder: (_, state) => const _ReviewHome()),
      GoRoute(
        path: '/groups/create',
        builder: (_, state) => const Scaffold(body: CollectionCreateScreen()),
      ),
      GoRoute(
        path: '/groups/:id/profile',
        builder: (_, state) => Scaffold(
          body: GroupProfileScreen(collectionId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/groups/:id/manage',
        builder: (_, state) => _ReviewHome(groupId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/groups/:id',
        builder: (_, state) => _ReviewHome(groupId: state.pathParameters['id']),
      ),
    ],
  );
  runApp(
    ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repository)],
      child: MaterialApp.router(
        title: 'Collect · local photo journey',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
}

class _ReviewHome extends ConsumerWidget {
  const _ReviewHome({this.groupId});
  final String? groupId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectRepositoryProvider);
    final current = state.collections
        .where((c) => c.id == (groupId ?? 'qa-private-group'))
        .firstOrNull;
    final named = [
      for (final (slug, name, type) in [
        ('buri-munsi', 'Buri munsi', 'ikimina'),
        ('gikundiro', 'Gikundiro', 'sport'),
      ])
        CollectCollection.fromJson({
          'id': 'qa-$slug',
          'slug': slug,
          'title': name,
          'is_public': true,
          'is_platform_sponsored': true,
          'collection_type': type,
          'created_at': '2026-09-06T00:00:00Z',
        }),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Local photo journey')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Fixture groups only',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Create group',
                expand: true,
                onPressed: () => context.go('/groups/create'),
              ),
              CollectSpacing.gap12,
              if (current != null) ...[
                CollectButton(
                  label: 'Edit group photo',
                  expand: true,
                  variant: CollectButtonVariant.secondary,
                  onPressed: () => context.go('/groups/${current.id}/profile'),
                ),
                CollectSpacing.gap16,
                GroupCard(
                  collection: current,
                  summary: const CollectionSummary(
                    amountRaisedRwf: 0,
                    supporterCount: 0,
                  ),
                ),
              ],
              for (final group in named) ...[
                CollectSpacing.gap16,
                GroupCard(
                  collection: group,
                  summary: const CollectionSummary(
                    amountRaisedRwf: 0,
                    supporterCount: 0,
                  ),
                  variant: GroupCardVariant.publicDiscovery,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
