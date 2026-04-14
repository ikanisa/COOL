import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/dense_admin_workspace_scaffold.dart';

import '../providers/admin_providers.dart';
import 'admin_savings_widgets.dart';

/// Admin screen for centralized savings group management.
///
/// Shows savings group overview metrics, group list with create/edit,
/// and community groups in read-only mode.
class AdminSavingsScreen extends ConsumerStatefulWidget {
  const AdminSavingsScreen({super.key});

  @override
  ConsumerState<AdminSavingsScreen> createState() => _AdminSavingsScreenState();
}

class _AdminSavingsScreenState extends ConsumerState<AdminSavingsScreen> {
  static const _autoRefreshInterval = Duration(seconds: 15);

  String _search = '';
  _SavingsTab _activeTab = _SavingsTab.savings;
  bool _showCreateForm = false;
  Timer? _autoRefreshTimer;

  // Create form controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _monthlyContributionController = TextEditingController();
  String _frequency = 'monthly';
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted) {
        return;
      }
      ref.invalidate(adminSavingsGroupsDetailProvider);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _nameController.dispose();
    _descriptionController.dispose();
    _targetAmountController.dispose();
    _monthlyContributionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final detailAsync = ref.watch(adminSavingsGroupsDetailProvider);

    return DenseAdminWorkspaceScaffold(
      title: Text(
        'Savings',
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      searchBar: CoolSearchField(
        hint: 'Search groups…',
        debounce: Duration.zero,
        onChanged: (v) => setState(() => _search = v),
      ),
      filterActions: [
        for (final tab in _SavingsTab.values) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              showCheckmark: false,
              label: Text(tab.label),
              selected: _activeTab == tab,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => _activeTab = tab);
              },
              backgroundColor: colors.chipBackground,
              selectedColor: colors.chipSelectedBackground,
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: _activeTab == tab
                    ? colors.primaryText
                    : colors.secondaryText,
              ),
              side: BorderSide.none,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(CoolRadii.pill)),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
      child: CoolAsyncView<Map<String, dynamic>>(
        value: detailAsync,
        onRetry: () => ref.invalidate(adminSavingsGroupsDetailProvider),
        loadingWidget: const Padding(
          padding: EdgeInsets.only(bottom: CoolSpace.x7),
          child: CoolSkeletonList(itemCount: 6),
        ),
        emptyCheck: (data) => data.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No group data',
          icon: CoolIcons.groupsOutlined,
        ),
        builder: (data) => _buildContent(data),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    final momoCode = data['savings_momo_code']?.toString() ?? '';
    final totalSavings = _asInt(data['total_savings_groups']);
    final activeSavings = _asInt(data['active_savings_groups']);
    final totalCommunity = _asInt(data['total_community_groups']);
    final totalMembers = _asInt(data['total_members_in_savings']);
    final totalCollected = _asInt(data['total_collected']);

    final savingsGroups = _parseGroups(data['savings_groups']);
    final communityGroups = _parseGroups(data['community_groups']);

    final query = _search.trim().toLowerCase();
    final activeGroups = _activeTab == _SavingsTab.savings
        ? savingsGroups
        : communityGroups;
    final filtered = activeGroups.where((g) {
      final name = (g['name']?.toString() ?? '').toLowerCase();
      return query.isEmpty || name.contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: CoolSpace.x7),
      children: [
        // ── MoMo code banner ──────────────────────────────
        if (momoCode.isNotEmpty) ...[
          CoolCard(
            backgroundColor: colors.info.withValues(alpha: 0.08),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.info.withValues(alpha: 0.14),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(CoolRadii.xs),
                    ),
                  ),
                  child: Icon(
                    CoolIcons.phoneAndroid,
                    size: 20,
                    color: colors.info,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Collection code',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.tertiaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        momoCode,
                        style: context.coolText.mono(
                          theme.textTheme.titleMedium,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(CoolIcons.copy, color: colors.info, size: 18),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: momoCode));
                    CoolToast.success(context, 'MoMo code copied');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
        ],

        // ── Metrics ───────────────────────────────────────
        const SizedBox(height: CoolSpace.x3),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            SavingsMetricTile(
              label: 'Savings Groups',
              value: '$totalSavings',
              icon: CoolIcons.savings,
              color: colors.accent,
            ),
            SavingsMetricTile(
              label: 'Active',
              value: '$activeSavings',
              icon: CoolIcons.checkCircle,
              color: colors.success,
            ),
            SavingsMetricTile(
              label: 'Community',
              value: '$totalCommunity',
              icon: CoolIcons.groupsFilled,
              color: colors.info,
            ),
            SavingsMetricTile(
              label: 'Members',
              value: '$totalMembers',
              icon: CoolIcons.person,
              color: colors.warning,
            ),
            SavingsMetricTile(
              label: 'Collected',
              value: formatWholeMoneyAmount(totalCollected),
              icon: CoolIcons.wallet,
              color: colors.success,
            ),
          ],
        ),

        // ── Create button (savings tab only) ──────────────
        if (_activeTab == _SavingsTab.savings) ...[
          const SizedBox(height: CoolSpace.x5),
          Material(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(CoolRadii.sm),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _showCreateForm = !_showCreateForm);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _showCreateForm ? CoolIcons.close : CoolIcons.add,
                      size: 18,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showCreateForm ? 'Cancel' : 'Create Savings Group',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // ── Create form ───────────────────────────────────
        if (_showCreateForm) ...[
          const SizedBox(height: CoolSpace.x4),
          CreateSavingsGroupForm(
            nameController: _nameController,
            descriptionController: _descriptionController,
            targetAmountController: _targetAmountController,
            monthlyContributionController: _monthlyContributionController,
            frequency: _frequency,
            isCreating: _isCreating,
            onFrequencyChanged: (v) => setState(() => _frequency = v),
            onSubmit: _handleCreateGroup,
          ),
        ],

        // ── Group list ────────────────────────────────────
        const SizedBox(height: CoolSpace.x5),
        if (query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: CoolSpace.x3),
            child: Text(
              '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.tertiaryText,
              ),
            ),
          ),
        if (filtered.isEmpty)
          CoolEmptyView(
            message: query.isEmpty
                ? 'No ${_activeTab == _SavingsTab.savings ? 'savings' : 'community'} groups yet'
                : 'No groups match your search',
            icon: CoolIcons.searchOff,
          )
        else
          for (final group in filtered) ...[
            SavingsGroupTile(
              group: group,
              isSavings: _activeTab == _SavingsTab.savings,
              onTap: _activeTab == _SavingsTab.savings
                  ? () => context.push(
                      AppRoutes.adminSavingsGroupDetail(
                        group['id']?.toString() ?? '',
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: CoolSpace.x3),
          ],
      ],
    );
  }

  Future<void> _handleCreateGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      CoolToast.error(context, 'Group name is required');
      return;
    }

    setState(() => _isCreating = true);
    try {
      final repo = ref.read(adminSavingsRepositoryProvider);
      final result = await repo.createSavingsGroup(
        name: name,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        targetAmount: int.tryParse(_targetAmountController.text.trim()),
        monthlyContribution: int.tryParse(
          _monthlyContributionController.text.trim(),
        ),
        frequency: _frequency,
      );

      if (!mounted) return;
      if (result['status'] == 'success') {
        CoolToast.success(context, 'Savings group created');
        _nameController.clear();
        _descriptionController.clear();
        _targetAmountController.clear();
        _monthlyContributionController.clear();
        setState(() {
          _showCreateForm = false;
          _isCreating = false;
        });
        ref.invalidate(adminSavingsGroupsDetailProvider);
      } else {
        throw StateError(result['message']?.toString() ?? 'Creation failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      CoolToast.error(context, e.toString());
    }
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
// Tab enum
// ═══════════════════════════════════════════════════════════════

enum _SavingsTab {
  savings('Savings'),
  community('Community');

  const _SavingsTab(this.label);
  final String label;
}
