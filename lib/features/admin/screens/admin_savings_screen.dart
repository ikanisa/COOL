import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/dense_admin_workspace_scaffold.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_search_field.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';

import '../providers/admin_providers.dart';

const BorderRadius _metricRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

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
  String _search = '';
  _SavingsTab _activeTab = _SavingsTab.savings;
  bool _showCreateForm = false;

  // Create form controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _monthlyContributionController = TextEditingController();
  String _frequency = 'monthly';
  bool _isCreating = false;

  @override
  void dispose() {
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
          icon: Icons.groups_outlined,
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
                    borderRadius: _metricRadius,
                  ),
                  child: Icon(
                    Icons.phone_android_rounded,
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
                  icon: Icon(Icons.copy_rounded, color: colors.info, size: 18),
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
            _MetricTile(
              label: 'Savings Groups',
              value: '$totalSavings',
              icon: Icons.savings_rounded,
              color: colors.accent,
            ),
            _MetricTile(
              label: 'Active',
              value: '$activeSavings',
              icon: Icons.check_circle_rounded,
              color: colors.success,
            ),
            _MetricTile(
              label: 'Community',
              value: '$totalCommunity',
              icon: Icons.groups_rounded,
              color: colors.info,
            ),
            _MetricTile(
              label: 'Members',
              value: '$totalMembers',
              icon: Icons.person_rounded,
              color: colors.warning,
            ),
            _MetricTile(
              label: 'Collected',
              value: formatWholeMoneyAmount(totalCollected),
              icon: Icons.account_balance_wallet_rounded,
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
                      _showCreateForm
                          ? Icons.close_rounded
                          : Icons.add_rounded,
                      size: 18,
                      color: colors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showCreateForm
                          ? 'Cancel'
                          : 'Create Savings Group',
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
          _CreateSavingsGroupForm(
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
            icon: Icons.search_off_rounded,
          )
        else
          for (final group in filtered) ...[
            _SavingsGroupTile(
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
        monthlyContribution:
            int.tryParse(_monthlyContributionController.text.trim()),
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

// ═══════════════════════════════════════════════════════════════
// Create form
// ═══════════════════════════════════════════════════════════════

class _CreateSavingsGroupForm extends StatelessWidget {
  const _CreateSavingsGroupForm({
    required this.nameController,
    required this.descriptionController,
    required this.targetAmountController,
    required this.monthlyContributionController,
    required this.frequency,
    required this.isCreating,
    required this.onFrequencyChanged,
    required this.onSubmit,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController targetAmountController;
  final TextEditingController monthlyContributionController;
  final String frequency;
  final bool isCreating;
  final ValueChanged<String> onFrequencyChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New Savings Group',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          _AdminTextField(
            controller: nameController,
            label: 'Group name',
            hint: 'e.g. Umuganda 2026',
          ),
          const SizedBox(height: CoolSpace.x3),
          _AdminTextField(
            controller: descriptionController,
            label: 'Description (optional)',
            hint: 'Brief description',
            maxLines: 2,
          ),
          const SizedBox(height: CoolSpace.x3),
          Row(
            children: [
              Expanded(
                child: _AdminTextField(
                  controller: targetAmountController,
                  label: 'Target (RWF)',
                  hint: '0',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: CoolSpace.x3),
              Expanded(
                child: _AdminTextField(
                  controller: monthlyContributionController,
                  label: 'Monthly (RWF)',
                  hint: '0',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Frequency',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Wrap(
            spacing: 8,
            children: [
              for (final freq in const ['monthly', 'weekly', 'one_off'])
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(freq.replaceAll('_', ' ')),
                  selected: frequency == freq,
                  onSelected: (_) => onFrequencyChanged(freq),
                  backgroundColor: colors.chipBackground,
                  selectedColor: colors.chipSelectedBackground,
                  labelStyle: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: frequency == freq
                        ? colors.primaryText
                        : colors.secondaryText,
                  ),
                  side: BorderSide.none,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(CoolRadii.pill),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x5),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isCreating ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(
                isCreating ? 'Creating…' : 'Create Savings Group',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
              borderRadius: _metricRadius,
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

class _SavingsGroupTile extends StatelessWidget {
  const _SavingsGroupTile({
    required this.group,
    required this.isSavings,
    this.onTap,
  });

  final Map<String, dynamic> group;
  final bool isSavings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final name = group['name']?.toString() ?? 'Unnamed';
    final memberCount = _asInt(group['member_count']);
    final isClosed = group['is_closed'] == true;
    final statusColor = isClosed ? colors.danger : colors.success;
    final total = _asInt(group['total_collected']);

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      onTap: onTap,
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
                  borderRadius: _metricRadius,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isSavings ? Icons.savings_rounded : Icons.groups_rounded,
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
                        '$memberCount member${memberCount == 1 ? '' : 's'}',
                        if (isSavings && total > 0)
                          '${formatWholeMoneyAmount(total)} RWF',
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
                  isClosed ? 'CLOSED' : 'ACTIVE',
                  style: context.coolText.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: CoolSpace.x2),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.tertiaryText,
                  size: 20,
                ),
              ],
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

class _AdminTextField extends StatelessWidget {
  const _AdminTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.bodyMedium?.copyWith(
              color: colors.tertiaryText,
            ),
            filled: true,
            fillColor: colors.chipBackground,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CoolRadii.sm),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
