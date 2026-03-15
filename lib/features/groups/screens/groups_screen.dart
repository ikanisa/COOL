import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
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

  Future<void> _openFiltersSheet() async {
    final selection = await showModalBottomSheet<_GroupFilterSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GroupsFilterSheet(
        typeFilter: _typeFilter,
        visibilityFilter: _visibilityFilter,
      ),
    );

    if (!mounted || selection == null) {
      return;
    }

    setState(() {
      _typeFilter = selection.typeFilter;
      _visibilityFilter = selection.visibilityFilter;
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
          onPressed: () => context.go(AppRoutes.home),
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      body: CoolScreenBackground(
        child: isLoading && groups.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      sliver: SliverToBoxAdapter(
                        child: Text(
                          l10n.navGroups,
                          style: GoogleFonts.dmSans(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: palette.text,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _GroupsHeroCard(
                              activeView: _activeView,
                              count: groups.length,
                              filterSummary: _filterSummary(),
                              createLabel: l10n.groupsCreateNewTitle,
                              onCreate: isDiscover
                                  ? null
                                  : () => context.push(AppRoutes.groupCreate),
                            ),
                            const SizedBox(height: 16),
                            _GroupsControlsCard(
                              activeView: _activeView,
                              filterSummary: _filterSummary(),
                              onViewChanged: (view) =>
                                  unawaited(_setActiveView(view)),
                              onOpenFilters: isDiscover
                                  ? null
                                  : () => unawaited(_openFiltersSheet()),
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    if (groups.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                        sliver: SliverToBoxAdapter(
                          child: _EmptyState(isDiscover: isDiscover),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
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

  String _filterSummary() {
    if (_activeView == _GroupsView.discover) {
      return 'Browse public groups you can join.';
    }

    final parts = <String>[];
    switch (_typeFilter) {
      case _GroupTypeFilter.all:
        break;
      case _GroupTypeFilter.saving:
        parts.add('Saving groups');
      case _GroupTypeFilter.community:
        parts.add('Community funds');
    }

    switch (_visibilityFilter) {
      case _GroupVisibilityFilter.all:
        break;
      case _GroupVisibilityFilter.privateOnly:
        parts.add('Private only');
      case _GroupVisibilityFilter.publicOnly:
        parts.add('Public only');
    }

    if (parts.isEmpty) {
      return 'All of your groups';
    }

    return parts.join(' · ');
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

  String get label {
    return switch (this) {
      _GroupTypeFilter.all => 'All types',
      _GroupTypeFilter.saving => 'Saving',
      _GroupTypeFilter.community => 'Community',
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

  String get label {
    return switch (this) {
      _GroupVisibilityFilter.all => 'Any visibility',
      _GroupVisibilityFilter.privateOnly => 'Private only',
      _GroupVisibilityFilter.publicOnly => 'Public only',
    };
  }
}

class _GroupFilterSelection {
  const _GroupFilterSelection({
    required this.typeFilter,
    required this.visibilityFilter,
  });

  final _GroupTypeFilter typeFilter;
  final _GroupVisibilityFilter visibilityFilter;
}

class _GroupsHeroCard extends StatelessWidget {
  const _GroupsHeroCard({
    required this.activeView,
    required this.count,
    required this.filterSummary,
    required this.createLabel,
    this.onCreate,
  });

  final _GroupsView activeView;
  final int count;
  final String filterSummary;
  final String createLabel;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isDiscover = activeView == _GroupsView.discover;
    final title = isDiscover ? 'Discover groups' : 'My groups';
    final subtitle = isDiscover
        ? 'Browse public savings circles and community funds without the extra dashboard noise.'
        : 'Keep your active circles, goals, and contribution progress in one calm list.';
    final tint = (isDiscover ? palette.blue : palette.accent).withValues(
      alpha: Theme.of(context).brightness == Brightness.light ? 0.10 : 0.16,
    );

    return CoolCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[palette.surface, palette.surface2, tint],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: palette.text2,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _HeroStatChip(
                  label: count == 1 ? '1 group' : '$count groups',
                  icon: Icons.groups_2_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    filterSummary,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: palette.text2,
                    ),
                  ),
                ),
              ],
            ),
            if (!isDiscover && onCreate != null) ...[
              const SizedBox(height: 18),
              CoolButton(label: createLabel, onTap: onCreate!),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: palette.text2),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupsControlsCard extends StatelessWidget {
  const _GroupsControlsCard({
    required this.activeView,
    required this.filterSummary,
    required this.onViewChanged,
    this.onOpenFilters,
  });

  final _GroupsView activeView;
  final String filterSummary;
  final ValueChanged<_GroupsView> onViewChanged;
  final VoidCallback? onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isDiscover = activeView == _GroupsView.discover;

    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TabPill(
                    label: 'My Groups',
                    isActive: !isDiscover,
                    onTap: () => onViewChanged(_GroupsView.mine),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TabPill(
                    label: 'Discover',
                    isActive: isDiscover,
                    onTap: () => onViewChanged(_GroupsView.discover),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    filterSummary,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: palette.text2,
                      height: 1.4,
                    ),
                  ),
                ),
                if (!isDiscover && onOpenFilters != null) ...[
                  const SizedBox(width: 12),
                  CoolButton(
                    label: 'Filters',
                    onTap: onOpenFilters!,
                    variant: CoolButtonVariant.secondary,
                    fullWidth: false,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupsFilterSheet extends StatefulWidget {
  const _GroupsFilterSheet({
    required this.typeFilter,
    required this.visibilityFilter,
  });

  final _GroupTypeFilter typeFilter;
  final _GroupVisibilityFilter visibilityFilter;

  @override
  State<_GroupsFilterSheet> createState() => _GroupsFilterSheetState();
}

class _GroupsFilterSheetState extends State<_GroupsFilterSheet> {
  late _GroupTypeFilter _typeFilter;
  late _GroupVisibilityFilter _visibilityFilter;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.typeFilter;
    _visibilityFilter = widget.visibilityFilter;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'My group filters',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Keep advanced filters here instead of always visible on the route.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: palette.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              _FilterSection<_GroupTypeFilter>(
                title: 'Type',
                options: _GroupTypeFilter.values,
                selected: _typeFilter,
                labelBuilder: (value) => value.label,
                onSelected: (value) => setState(() => _typeFilter = value),
              ),
              const SizedBox(height: 18),
              _FilterSection<_GroupVisibilityFilter>(
                title: 'Visibility',
                options: _GroupVisibilityFilter.values,
                selected: _visibilityFilter,
                labelBuilder: (value) => value.label,
                onSelected: (value) =>
                    setState(() => _visibilityFilter = value),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: CoolButton(
                      label: 'Reset',
                      variant: CoolButtonVariant.secondary,
                      onTap: () {
                        Navigator.of(context).pop(
                          const _GroupFilterSelection(
                            typeFilter: _GroupTypeFilter.all,
                            visibilityFilter: _GroupVisibilityFilter.all,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CoolButton(
                      label: 'Apply',
                      onTap: () {
                        Navigator.of(context).pop(
                          _GroupFilterSelection(
                            typeFilter: _typeFilter,
                            visibilityFilter: _visibilityFilter,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSection<T> extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.text2,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              _FilterChipButton(
                label: labelBuilder(option),
                isSelected: option == selected,
                onTap: () => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? palette.accentGlow : palette.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? palette.accent : palette.text2,
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
    final meta = group.bankPartner != null
        ? l10n.groupsBankCustodianMeta(group.bankPartner!)
        : group.momoNumber != null
        ? l10n.groupsMomoRouteMeta(group.momoNumber!)
        : group.type == 'saving'
        ? l10n.groupsSavingGroupMeta
        : l10n.groupsCommunityFundMeta;

    return CoolCard(
      onTap: () {
        final id = group.id;
        if (id != null && id.isNotEmpty) {
          context.push('/groups/$id');
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (group.type == 'saving')
                  const StatusBadge.saving()
                else
                  const StatusBadge.community(),
                const SizedBox(width: 6),
                if (group.visibility == 'public')
                  const StatusBadge.public()
                else
                  const StatusBadge.private(),
                const Spacer(),
                Text(
                  '${_formatAmount(group.amount)} RWF',
                  style: GoogleFonts.dmMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: group.type == 'saving'
                        ? palette.accent
                        : palette.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              group.name,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$meta · ${l10n.memberCount(group.memberCount)}',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: palette.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: palette.surface3,
                color: group.type == 'saving' ? palette.accent : palette.orange,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '$percent% of target',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.text3,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: palette.text3),
              ],
            ),
          ],
        ),
      ),
    );
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
          title: 'Could not load groups',
          message: error,
          actionLabel: 'Try again',
          onAction: () => unawaited(onRetry()),
        ),
      ),
    );
  }
}
