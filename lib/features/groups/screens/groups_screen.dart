import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_state_view.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';

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
      _visibilityFilter =
          _visibilityFilter == filter ? _GroupVisibilityFilter.all : filter;
    });
    await _loadActiveView();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final groups = ref.watch(groupsListProvider);
    final isLoading = ref.watch(groupsListLoadingProvider);
    final error = ref.watch(groupsListErrorProvider);
    final isDiscover = _activeView == _GroupsView.discover;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      body: CoolScreenBackground(
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
                      padding: CoolLayout.rootPagePadding.copyWith(bottom: 0, top: 0),
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
                      padding: const EdgeInsets.symmetric(horizontal: CoolLayout.horizontalPagePadding),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _GroupsHeroCard(
                              activeView: _activeView,
                              typeFilter: _typeFilter,
                              visibilityFilter: _visibilityFilter,
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
                            const SizedBox(height: 20),
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
                              const SizedBox(height: 12),
                        ),
                      ),
                  ],
                ),
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



class _GroupsHeroCard extends StatelessWidget {
  const _GroupsHeroCard({
    required this.activeView,
    required this.typeFilter,
    required this.visibilityFilter,
    required this.createLabel,
    required this.onViewChanged,
    required this.onToggleType,
    required this.onToggleVisibility,
    this.onCreate,
  });

  final _GroupsView activeView;
  final _GroupTypeFilter typeFilter;
  final _GroupVisibilityFilter visibilityFilter;
  final String createLabel;
  final ValueChanged<_GroupsView> onViewChanged;
  final ValueChanged<_GroupTypeFilter> onToggleType;
  final ValueChanged<_GroupVisibilityFilter> onToggleVisibility;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final isDiscover = activeView == _GroupsView.discover;

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TabPill(
                    label: context.l10n.myGroups,
                    isActive: !isDiscover,
                    onTap: () => onViewChanged(_GroupsView.mine),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TabPill(
                    label: context.l10n.discover,
                    isActive: isDiscover,
                    onTap: () => onViewChanged(_GroupsView.discover),
                  ),
                ),
              ],
            ),
            if (!isDiscover) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _FilterIconButton(
                    tooltip: context.l10n.savings,
                    icon: Icons.savings_outlined,
                    isActive: typeFilter == _GroupTypeFilter.saving,
                    onTap: () => onToggleType(_GroupTypeFilter.saving),
                  ),
                  const SizedBox(width: 14),
                  _FilterIconButton(
                    tooltip: context.l10n.peopleOutline,
                    icon: Icons.people_outline_rounded,
                    isActive: typeFilter == _GroupTypeFilter.community,
                    onTap: () => onToggleType(_GroupTypeFilter.community),
                  ),
                  const SizedBox(width: 14),
                  _FilterIconButton(
                    tooltip: context.l10n.lockOutline,
                    icon: Icons.lock_outline_rounded,
                    isActive: visibilityFilter == _GroupVisibilityFilter.privateOnly,
                    onTap: () => onToggleVisibility(_GroupVisibilityFilter.privateOnly),
                  ),
                  const SizedBox(width: 14),
                  _FilterIconButton(
                    tooltip: 'Public',
                    icon: Icons.public_rounded,
                    isActive: visibilityFilter == _GroupVisibilityFilter.publicOnly,
                    onTap: () => onToggleVisibility(_GroupVisibilityFilter.publicOnly),
                  ),
                ],
              ),
            ],
            if (!isDiscover && onCreate != null) ...[
              const SizedBox(height: 24),
              CoolButton(label: createLabel, onTap: onCreate!),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterIconButton extends StatelessWidget {
  const _FilterIconButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      label: tooltip ?? 'Filter',
      selected: isActive,
      child: Tooltip(
        message: tooltip ?? '',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive ? palette.accentGlow : palette.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive ? palette.accent : palette.border,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isActive ? palette.accent : palette.text3,
            ),
          ),
        ),
      ),
    );
  }
}



class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDiscover});

  final bool isDiscover;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CoolStateView.empty(
      title: isDiscover ? l10n.groupsEmptyPublicTitle : l10n.noGroupsYet,
      message: isDiscover
          ? l10n.groupsEmptyPublicMessage
          : l10n.groupsEmptyPrivateMessage,
      icon: Icons.groups_2_outlined,
    );
  }
}

class _GroupListItem extends StatelessWidget {
  const _GroupListItem({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final l10n = context.l10n;
    final progress = group.targetAmount > 0
        ? (group.amount / group.targetAmount).clamp(0.0, 1.0)
        : 0.0;
    final percent = (progress * 100).round();
    final accentColor =
        group.type == 'saving' ? palette.accent : palette.orange;

    return CoolCard(
      onTap: () {
        final id = group.id;
        if (id != null && id.isNotEmpty) {
          context.push('/groups/$id');
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Line 1: Amount ────────────────────────────────────
            Text(
              '${_formatAmount(group.amount)} RWF',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),

            // ── Line 2: Group name ───────────────────────────────
            Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),

            // ── Line 3: Metadata chips ───────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (group.momoNumber != null &&
                    group.momoNumber!.trim().isNotEmpty)
                  _MetaChip(label: _shortenPhone(group.momoNumber!)),
                if (group.type == 'saving')
                    StatusBadge.saving()
                else
                    StatusBadge.community(),
                if (group.visibility == 'public')
                    StatusBadge.public()
                else
                    StatusBadge.private(),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.memberCount(group.memberCount),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),

            // ── Progress bar ─────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: palette.surface3,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '$percent% of target',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.text3,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_rounded, color: palette.text3, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Shortens phone: "+250788123456" or "250788123456" → "0788123456".
  static String _shortenPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[\s\-]'), '');
    if (cleaned.startsWith('+250')) return '0${cleaned.substring(4)}';
    if (cleaned.startsWith('250') && cleaned.length >= 12) {
      return '0${cleaned.substring(3)}';
    }
    return cleaned;
  }

  static String _formatAmount(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text2,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: CoolStateView.error(
          title: 'Load groups failed',
          message: error,
          actionLabel: 'Try again',
          action: () => unawaited(onRetry()),
        ),
      ),
    );
  }
}