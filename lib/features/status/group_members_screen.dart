import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class GroupMembersScreen extends ConsumerStatefulWidget {
  const GroupMembersScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends ConsumerState<GroupMembersScreen> {
  final _search = TextEditingController();
  String _query = '';
  _MemberFilter _filter = _MemberFilter.all;
  _MemberSort _sort = _MemberSort.contribution;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(groupMembersProvider(widget.collectionId));
    final contributions = ref.watch(
      contributionsForCollectionProvider(widget.collectionId),
    );
    final contributionTotals = <String, int>{};
    for (final contribution in contributions) {
      contributionTotals.update(
        contribution.supporterLabel,
        (amount) => amount + contribution.amountRwf,
        ifAbsent: () => contribution.amountRwf,
      );
    }
    return ScreenScaffold(
      title: 'Members',
      showHeader: false,
      children: [
        const _MembersPageHeader(),
        SearchWithClearField(
          controller: _search,
          label: 'Search Collect ID',
          onChanged: (value) => setState(() => _query = value),
        ),
        members.when(
          data: (items) {
            final query = _query.trim().toLowerCase();
            final visible = query.isEmpty
                ? items
                : [
                    for (final item in items)
                      if (item.safeLabel.toLowerCase().contains(query) ||
                          item.role.toLowerCase().contains(query))
                        item,
                  ];
            final filtered =
                visible.where((item) {
                  return switch (_filter) {
                    _MemberFilter.all => true,
                    _MemberFilter.owner => item.role == 'owner',
                    _MemberFilter.active => item.status == 'active',
                  };
                }).toList()..sort(
                  (left, right) =>
                      _compareMembers(left, right, _sort, contributionTotals),
                );
            if (items.isEmpty) {
              return const EmptyIllustrationState(
                icon: CollectIcons.people,
                title: 'No members yet',
                message:
                    'Members appear after they join from a group QR or deep link.',
              );
            }
            if (filtered.isEmpty) {
              return EmptySearchState(
                title: 'No members found',
                message: 'No Collect ID or role matches that search.',
                onClear: () => setState(() {
                  _search.clear();
                  _query = '';
                }),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MemberControlDock(
                  filterLabel: _memberFilterLabel(_filter),
                  sortLabel: _memberSortLabel(_sort),
                  onFilterTap: _showMemberFilterSheet,
                  onSortTap: _showMemberSortSheet,
                ),
                CollectSpacing.gap12,
                SectionHeader(
                  title: 'Roster',
                  actionLabel: '${filtered.length}',
                ),
                CollectCard(
                  emphasis: CollectCardEmphasis.flat,
                  child: Column(
                    children: [
                      for (final member in filtered)
                        FinancialListRow(
                          title: compactCollectIdLabel(member.safeLabel),
                          amountRwf: contributionTotals[member.safeLabel] ?? 0,
                          meta: formatCollectDateTime(member.joinedAt),
                          subtitle: _memberSubtitle(member),
                          leading: CollectIcons.profile,
                          tone: member.role == 'owner'
                              ? CollectStatusTone.privacy
                              : CollectStatusTone.success,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => const LoadingStatePanel(
            title: 'Loading members',
            message: 'Fetching group members and Collect ID roles.',
            icon: CollectIcons.people,
            lines: 4,
          ),
          error: (error, _) => CollectErrorState(
            title: 'Could not load members',
            message: error.toString(),
          ),
        ),
      ],
    );
  }

  void _showMemberSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return CollectBottomSheet(
          child: _MemberOptionSheet<_MemberSort>(
            title: 'Sort members',
            values: _MemberSort.values,
            selected: _sort,
            labelFor: _memberSortLabel,
            onSelected: (sort) {
              setState(() => _sort = sort);
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  void _showMemberFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: context.collectColors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return CollectBottomSheet(
          child: _MemberOptionSheet<_MemberFilter>(
            title: 'Filter members',
            values: _MemberFilter.values,
            selected: _filter,
            labelFor: _memberFilterLabel,
            onSelected: (filter) {
              setState(() => _filter = filter);
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }
}

class _MembersPageHeader extends StatelessWidget {
  const _MembersPageHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Semantics(
      container: true,
      header: true,
      label: 'Members',
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Back',
            style: IconButton.styleFrom(
              backgroundColor: foreground.withValues(alpha: 0.10),
              foregroundColor: foreground,
              side: BorderSide(color: foreground.withValues(alpha: 0.16)),
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
            ),
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Text(
              'Members',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberControlDock extends StatelessWidget {
  const _MemberControlDock({
    required this.filterLabel,
    required this.sortLabel,
    required this.onFilterTap,
    required this.onSortTap,
  });

  final String filterLabel;
  final String sortLabel;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MemberControlButton(
            icon: CollectIcons.people,
            title: 'Members',
            value: filterLabel,
            onTap: onFilterTap,
          ),
        ),
        CollectSpacing.gapW12,
        Expanded(
          child: _MemberControlButton(
            icon: CollectIcons.activity,
            title: 'Sort',
            value: sortLabel,
            onTap: onSortTap,
          ),
        ),
      ],
    );
  }
}

class _MemberControlButton extends StatelessWidget {
  const _MemberControlButton({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      label: '$title $value',
      child: Material(
        color: colors.glassControl,
        borderRadius: CollectRadius.pillBorder,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(color: colors.glassBorder),
          ),
          child: InkWell(
            borderRadius: CollectRadius.pillBorder,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x3,
                vertical: CollectSpacing.x2,
              ),
              child: Row(
                children: [
                  Icon(icon, color: colors.actionColor, size: 20),
                  CollectSpacing.gapW8,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: CollectTypography.eyebrowLabel(
                            colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(CollectIcons.chevron, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberOptionSheet<T> extends StatelessWidget {
  const _MemberOptionSheet({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          CollectSpacing.gap12,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              for (final value in values)
                _MemberSheetPill<T>(
                  value: value,
                  label: labelFor(value),
                  selected: selected == value,
                  onSelected: onSelected,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberSheetPill<T> extends StatelessWidget {
  const _MemberSheetPill({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final T value;
  final String label;
  final bool selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filter option $label',
      child: Material(
        color: selected ? colors.actionColor : colors.glassControl,
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: () => onSelected(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x3,
              vertical: CollectSpacing.x2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? CollectIcons.check : CollectIcons.filter,
                  size: 18,
                  color: selected
                      ? colors.selectedOnAccent
                      : colors.textSecondary,
                ),
                CollectSpacing.gapW8,
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colors.selectedOnAccent
                        : colors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _MemberFilter { all, owner, active }

enum _MemberSort { contribution, newest, collectId }

String _memberFilterLabel(_MemberFilter filter) {
  return switch (filter) {
    _MemberFilter.all => 'All',
    _MemberFilter.owner => 'Owner',
    _MemberFilter.active => 'Active',
  };
}

String _memberSortLabel(_MemberSort sort) {
  return switch (sort) {
    _MemberSort.contribution => 'Top',
    _MemberSort.newest => 'Newest',
    _MemberSort.collectId => 'Collect ID',
  };
}

int _compareMembers(
  CollectMember left,
  CollectMember right,
  _MemberSort sort,
  Map<String, int> totals,
) {
  return switch (sort) {
    _MemberSort.contribution => (totals[right.safeLabel] ?? 0).compareTo(
      totals[left.safeLabel] ?? 0,
    ),
    _MemberSort.newest => right.joinedAt.compareTo(left.joinedAt),
    _MemberSort.collectId => left.publicId.compareTo(right.publicId),
  };
}

String _memberSubtitle(CollectMember member) {
  final role = member.role == 'owner' ? 'Owner' : 'Member';
  final status = _memberStatusLabel(member.status);
  return '$role · $status';
}

String _memberStatusLabel(String status) {
  final normalized = status.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return 'Unknown';
  return normalized
      .split(RegExp(r'\s+'))
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}
