import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/dense_admin_workspace_scaffold.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/admin_section_header.dart';

import '../providers/admin_providers.dart';

EdgeInsets _groupsListPadding() => const EdgeInsets.only(bottom: CoolSpace.x7);

const BorderRadius _groupMetricRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

/// Admin screen for viewing all contribution groups with aggregate stats.
class AdminGroupsScreen extends ConsumerStatefulWidget {
  const AdminGroupsScreen({super.key});

  @override
  ConsumerState<AdminGroupsScreen> createState() => _AdminGroupsScreenState();
}

class _AdminGroupsScreenState extends ConsumerState<AdminGroupsScreen> {
  String _search = '';
  String? _statusFilter;

  static const _statusFilters = [
    null, // all
    'active',
    'closed',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryAsync = ref.watch(adminGroupsSummaryProvider);
    final filterChips = _statusFilters
        .map<Widget>((filter) {
          final colors = context.coolSemanticColors;
          final isSelected = _statusFilter == filter;
          final label = filter == null
              ? 'All'
              : '${filter[0].toUpperCase()}${filter.substring(1)}';
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              showCheckmark: false,
              label: Text(label),
              selected: isSelected,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => _statusFilter = filter);
              },
              backgroundColor: colors.chipBackground,
              selectedColor: colors.chipSelectedBackground,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected ? colors.primaryText : colors.secondaryText,
              ),
              side: BorderSide.none,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(CoolRadii.pill)),
              ),
              visualDensity: VisualDensity.compact,
            ),
          );
        })
        .toList(growable: false);

    return DenseAdminWorkspaceScaffold(
      title: Text(
        'Contribution Groups',
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      subtitle: Text(
        'Platform-wide group overview and member counts',
        style: theme.textTheme.bodySmall?.copyWith(
          color: context.coolSemanticColors.secondaryText,
          fontWeight: FontWeight.w700,
        ),
      ),
      searchBar: CoolSearchField(
        hint: 'Search groups…',
        debounce: Duration.zero,
        onChanged: (v) => setState(() => _search = v),
      ),
      filterActions: filterChips,
      child: CoolAsyncView<Map<String, dynamic>>(
        value: summaryAsync,
        onRetry: () => ref.invalidate(adminGroupsSummaryProvider),
        loadingWidget: Padding(
          padding: _groupsListPadding(),
          child: const CoolSkeletonList(itemCount: 6),
        ),
        emptyCheck: (data) => data.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No group data',
          icon: Icons.groups_outlined,
        ),
        builder: (data) {
          final colors = context.coolSemanticColors;
          final totalGroups = _asInt(data['total_groups']);
          final activeGroups = _asInt(data['active_groups']);
          final closedGroups = _asInt(data['closed_groups']);
          final privateGroups = _asInt(data['private_groups']);
          final totalMembers = _asInt(data['total_members']);
          final totalWallets = _asInt(data['total_wallets']);

          final groups = _parseGroups(data['groups']);
          final query = _search.trim().toLowerCase();
          final filtered = groups.where((g) {
            final name = (g['name']?.toString() ?? '').toLowerCase();
            final status = (g['status']?.toString() ?? '').toLowerCase();
            if (_statusFilter != null && status != _statusFilter) {
              return false;
            }
            if (query.isNotEmpty && !name.contains(query)) {
              return false;
            }
            return true;
          }).toList();

          return ListView(
            padding: _groupsListPadding(),
            children: [
              const AdminSectionHeader(title: 'Overview'),
              const SizedBox(height: CoolSpace.x3),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  _MetricTile(
                    label: 'Total Groups',
                    value: '$totalGroups',
                    icon: Icons.groups_rounded,
                    color: colors.info,
                  ),
                  _MetricTile(
                    label: 'Active',
                    value: '$activeGroups',
                    icon: Icons.check_circle_rounded,
                    color: colors.success,
                  ),
                  _MetricTile(
                    label: 'Closed',
                    value: '$closedGroups',
                    icon: Icons.cancel_rounded,
                    color: colors.danger,
                  ),
                  _MetricTile(
                    label: 'Members',
                    value: '$totalMembers',
                    icon: Icons.person_rounded,
                    color: colors.accent,
                  ),
                  _MetricTile(
                    label: 'Private',
                    value: '$privateGroups',
                    icon: Icons.lock_rounded,
                    color: colors.warning,
                  ),
                  _MetricTile(
                    label: 'Wallets',
                    value: '$totalWallets',
                    icon: Icons.account_balance_wallet_rounded,
                    color: colors.warning,
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x6),
              const AdminSectionHeader(title: 'Group List'),
              const SizedBox(height: CoolSpace.x3),
              if (query.isNotEmpty || _statusFilter != null) ...[
                const SizedBox(height: CoolSpace.x2),
                Text(
                  '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.tertiaryText,
                  ),
                ),
              ],
              const SizedBox(height: CoolSpace.x4),
              if (filtered.isEmpty)
                const CoolEmptyView(
                  message: 'No groups match your filter',
                  icon: Icons.search_off_rounded,
                )
              else
                for (final group in filtered) ...[
                  _GroupTile(group: group),
                  const SizedBox(height: CoolSpace.x3),
                ],
            ],
          );
        },
      ),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static List<Map<String, dynamic>> _parseGroups(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
    }
    return const [];
  }
}

// ═══════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return CoolCard(
      backgroundColor: colors.analyticsSurface,
      useGradient: false,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: _groupMetricRadius,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.tertiaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final Map<String, dynamic> group;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final name = group['name']?.toString() ?? 'Unnamed';
    final type = group['type']?.toString() ?? '';
    final status = group['status']?.toString() ?? 'active';
    final visibility = group['visibility']?.toString() ?? 'public';
    final memberCount = _asInt(group['member_count']);
    final walletCount = _asInt(group['wallet_count']);
    final country = group['country']?.toString() ?? '';
    final isActive = status == 'active';
    final statusColor = isActive ? colors.success : colors.danger;

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: _groupMetricRadius,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isActive ? Icons.groups_rounded : Icons.group_off_rounded,
                  size: 20,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (type.isNotEmpty) type,
                        visibility,
                        if (country.isNotEmpty) country,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(CoolRadii.pill),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: context.coolText.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: CoolSpace.x3,
            runSpacing: CoolSpace.x2,
            children: [
              _StatChip(
                icon: Icons.person_rounded,
                label: '$memberCount member${memberCount == 1 ? '' : 's'}',
              ),
              if (walletCount > 0)
                _StatChip(
                  icon: Icons.account_balance_wallet_rounded,
                  label: '$walletCount wallet${walletCount == 1 ? '' : 's'}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.tertiaryText),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.tertiaryText,
          ),
        ),
      ],
    );
  }
}
