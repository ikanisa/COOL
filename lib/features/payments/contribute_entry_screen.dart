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
    final query = _query.trim().toLowerCase();
    final visibleCollections = collections.where((collection) {
      if (query.isEmpty) return true;
      return collection.title.toLowerCase().contains(query) ||
          collection.collectionType.label.toLowerCase().contains(query) ||
          (collection.purposeLabel ?? '').toLowerCase().contains(query);
    }).toList()..sort(_compareCollections);
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
        actions: [
          CollectChromeAction(
            icon: CollectIcons.qr,
            tooltip: 'Scan group QR',
            onPressed: () => context.go('/groups/scan'),
          ),
        ],
      ),
      onRefresh: () =>
          ref.read(collectRepositoryProvider.notifier).loadInitial(),
      children: isInitialLoading
          ? const [
              CollectScreenLoadingState(
                title: 'Loading groups',
                message: 'Refreshing the groups you can support.',
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
              if (collections.isEmpty)
                EmptyIllustrationState(
                  icon: CollectIcons.donate,
                  title: 'No groups available',
                  message:
                      'Scan a group QR to find the group you want to support.',
                  action: CollectButton(
                    label: 'Scan group QR',
                    icon: CollectIcons.qr,
                    onPressed: () => context.go('/groups/scan'),
                  ),
                )
              else if (visibleCollections.isEmpty)
                EmptySearchState(
                  title: 'No matching groups',
                  message: 'Try another group name, type, or purpose.',
                  onClear: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                )
              else
                GroupListPanel(
                  collections: visibleCollections,
                  summaries: summaries,
                  onGroupTap: (collection) =>
                      context.go('/groups/${collection.id}/contribute'),
                ),
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

int _compareCollections(CollectCollection left, CollectCollection right) {
  return left.title.toLowerCase().compareTo(right.title.toLowerCase());
}
