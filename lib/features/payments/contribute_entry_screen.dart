import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_group_cards.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ContributeEntryScreen extends ConsumerStatefulWidget {
  const ContributeEntryScreen({super.key});

  @override
  ConsumerState<ContributeEntryScreen> createState() =>
      _ContributeEntryScreenState();
}

class _ContributeEntryScreenState extends ConsumerState<ContributeEntryScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final collections = ref.watch(activeCollectionsProvider);
    final summaries = ref.watch(collectionSummariesProvider);
    final profile = state.currentProfile;
    final query = _query.trim().toLowerCase();
    final privateCollections = collections.where((collection) {
      return !collection.isPublic &&
          profile != null &&
          (collection.creatorUserId == profile.id ||
              collection.isCurrentUserMember);
    }).toList()..sort(_compareCollections);
    final publicCollections =
        collections.where((collection) => collection.isPublic).toList()
          ..sort(_compareCollections);
    final visiblePrivateCollections = _matchingCollections(
      privateCollections,
      query,
    );
    final visiblePublicCollections = _matchingCollections(
      publicCollections,
      query,
    );
    final hasAvailableGroups =
        privateCollections.isNotEmpty || publicCollections.isNotEmpty;
    final hasVisibleGroups =
        visiblePrivateCollections.isNotEmpty ||
        visiblePublicCollections.isNotEmpty;
    final isInitialLoading = state.isLoading && collections.isEmpty;

    return ScreenScaffold(
      title: 'Contribute',
      showHeader: false,
      compact: true,
      topChrome: CollectScreenTopChrome(
        avatarLabel: state.currentProfile?.publicId,
        avatarTooltip: 'Profile',
        searchLabel: 'Search groups',
        onAvatarTap: () => context.go('/settings'),
        onSearchTap: _beginSearch,
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: isInitialLoading
          ? const [
              CollectScreenLoadingState(
                title: 'Loading groups',
                message: 'Refreshing the groups you can contribute to.',
                icon: CollectIcons.donate,
                skeletonCount: 3,
              ),
            ]
          : [
              const SectionHeader(title: 'Choose a group'),
              if (_searching)
                SearchWithClearField(
                  controller: _search,
                  focusNode: _searchFocus,
                  label: 'Search group or purpose',
                  onChanged: (value) => setState(() => _query = value),
                ),
              if (!hasAvailableGroups)
                EmptyIllustrationState(
                  icon: CollectIcons.public,
                  title: 'Explore public groups',
                  message:
                      'Browse public groups and choose one to contribute to.',
                  action: CollectButton(
                    label: 'Explore public groups',
                    icon: CollectIcons.public,
                    onPressed: () => context.go('/groups'),
                  ),
                )
              else if (!hasVisibleGroups)
                EmptySearchState(
                  title: 'No matching groups',
                  message: 'Try another group name, type, or purpose.',
                  onClear: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                )
              else ...[
                if (visiblePrivateCollections.isNotEmpty) ...[
                  const SectionHeader(title: 'Your groups'),
                  GroupListPanel(
                    collections: visiblePrivateCollections,
                    summaries: summaries,
                    onGroupTap: (collection) =>
                        context.go('/groups/${collection.id}/contribute'),
                  ),
                ],
                if (visiblePublicCollections.isNotEmpty) ...[
                  const SectionHeader(title: 'Public groups'),
                  GroupListPanel(
                    collections: visiblePublicCollections,
                    summaries: summaries,
                    onGroupTap: (collection) =>
                        context.go('/groups/${collection.id}/contribute'),
                  ),
                ],
              ],
            ],
    );
  }

  void _beginSearch() {
    if (!_searching) {
      setState(() => _searching = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }
}

List<CollectCollection> _matchingCollections(
  List<CollectCollection> collections,
  String query,
) {
  if (query.isEmpty) return collections;
  return [
    for (final collection in collections)
      if (collection.title.toLowerCase().contains(query) ||
          collection.collectionType.label.toLowerCase().contains(query) ||
          (collection.purposeLabel ?? '').toLowerCase().contains(query))
        collection,
  ];
}

int _compareCollections(CollectCollection left, CollectCollection right) {
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
