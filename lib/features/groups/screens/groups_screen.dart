import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_glass_card.dart';
import '../../../shared/widgets/core_tab_root_scaffold.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_state_view.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../../partners/providers/partner_provider.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';

part 'groups_screen_parts.dart';

/// Groups landing route focused on two jobs: manage your groups or discover one.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

enum _GroupsView { mine, discover }

enum _GroupTypeFilter { all, saving, community }

enum _GroupVisibilityFilter { all, privateOnly, publicOnly }

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  _GroupsView _activeView = _GroupsView.mine;
  _GroupTypeFilter _typeFilter = _GroupTypeFilter.all;
  _GroupVisibilityFilter _visibilityFilter = _GroupVisibilityFilter.all;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadActiveView);
  }

  Future<void> _loadActiveView() async {
    final notifier = ref.read(groupsProvider.notifier);
    if (_activeView == _GroupsView.discover) {
      await notifier.loadPublicGroups();
      return;
    }

    await notifier.loadFilteredMyGroups(
      type: _typeFilter.backendValue,
      visibility: _visibilityFilter.backendValue,
    );
  }

  Future<void> _setActiveView(_GroupsView view) async {
    if (_activeView == view) {
      return;
    }

    setState(() => _activeView = view);
    await _loadActiveView();
  }

  Future<void> _refreshActiveView() => _loadActiveView();

  Future<void> _toggleTypeFilter(_GroupTypeFilter filter) async {
    setState(() {
      _typeFilter = _typeFilter == filter ? _GroupTypeFilter.all : filter;
    });
    await _loadActiveView();
  }

  Future<void> _toggleVisibilityFilter(_GroupVisibilityFilter filter) async {
    setState(() {
      _visibilityFilter = _visibilityFilter == filter
          ? _GroupVisibilityFilter.all
          : filter;
    });
    await _loadActiveView();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final groups = ref.watch(groupsListProvider);
    final isLoading = ref.watch(groupsListLoadingProvider);
    final error = ref.watch(groupsListErrorProvider);
    final isDiscover = _activeView == _GroupsView.discover;
    final hasBankPartner = ref.watch(hasActiveBankPartnerProvider);

    return CoreTabRootScaffold(
      child: isLoading && groups.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: CoolLayout.horizontalPagePadding,
                vertical: CoolLayout.verticalPagePadding,
              ),
              child: CoolSkeletonList(),
            )
          : error != null && groups.isEmpty
          ? _ErrorState(error: error, onRetry: _refreshActiveView)
          : RefreshIndicator(
              onRefresh: _refreshActiveView,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: CoolLayout.rootPagePadding.copyWith(
                      bottom: 0,
                      top: 0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        l10n.navGroups,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CoolLayout.horizontalPagePadding,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GroupsHeroCard(
                            activeView: _activeView,
                            typeFilter: _typeFilter,
                            visibilityFilter: _visibilityFilter,
                            hasBankPartner: hasBankPartner,
                            createLabel: l10n.groupsCreateNewTitle,
                            onViewChanged: (view) =>
                                unawaited(_setActiveView(view)),
                            onToggleType: (f) =>
                                unawaited(_toggleTypeFilter(f)),
                            onToggleVisibility: (f) =>
                                unawaited(_toggleVisibilityFilter(f)),
                            onCreate: isDiscover
                                ? null
                                : () => context.push(AppRoutes.groupCreate),
                          ),
                          const SizedBox(height: CoolSpace.x5),
                        ],
                      ),
                    ),
                  ),
                  if (groups.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        CoolLayout.horizontalPagePadding,
                        0,
                        CoolLayout.horizontalPagePadding,
                        CoolLayout.rootBottomClearance +
                            CoolLayout.fabBottomClearance / 2,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _EmptyState(isDiscover: isDiscover),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        CoolLayout.horizontalPagePadding,
                        0,
                        CoolLayout.horizontalPagePadding,
                        CoolLayout.rootBottomClearance +
                            CoolLayout.fabBottomClearance / 2,
                      ),
                      sliver: SliverList.separated(
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          return _GroupListItem(group: groups[index]);
                        },
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: CoolSpace.x3),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

extension on _GroupTypeFilter {
  String? get backendValue {
    return switch (this) {
      _GroupTypeFilter.all => null,
      _GroupTypeFilter.saving => 'saving',
      _GroupTypeFilter.community => 'community',
    };
  }
}

extension on _GroupVisibilityFilter {
  String? get backendValue {
    return switch (this) {
      _GroupVisibilityFilter.all => null,
      _GroupVisibilityFilter.privateOnly => 'private',
      _GroupVisibilityFilter.publicOnly => 'public',
    };
  }
}


