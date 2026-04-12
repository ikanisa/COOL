import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_toast.dart';

import '../providers/admin_providers.dart';

const BorderRadius _chipRadius = BorderRadius.all(
  Radius.circular(CoolRadii.xs),
);

/// Detail screen for a single savings group.
///
/// Shows group info, member list with add/remove, and manual
/// allocation form for contributions.
class AdminSavingsDetailScreen extends ConsumerStatefulWidget {
  const AdminSavingsDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<AdminSavingsDetailScreen> createState() =>
      _AdminSavingsDetailScreenState();
}

class _AdminSavingsDetailScreenState
    extends ConsumerState<AdminSavingsDetailScreen> {
  _DetailTab _activeTab = _DetailTab.members;

  // ── Allocation form controllers ──
  String? _selectedMemberUserId;
  final _allocationAmountController = TextEditingController();
  final _allocationNoteController = TextEditingController();
  bool _isAllocating = false;

  // ── Add member controllers ──
  final _addMemberPhoneController = TextEditingController();
  final _addMemberNameController = TextEditingController();
  bool _isAddingMember = false;

  @override
  void dispose() {
    _allocationAmountController.dispose();
    _allocationNoteController.dispose();
    _addMemberPhoneController.dispose();
    _addMemberNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final detailAsync = ref.watch(adminSavingsGroupsDetailProvider);

    return AdminDetailScaffold(
      title: Text(
        context.l10n.adminSavingsGroupTitle,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      child: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Error: $error',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.danger,
            ),
          ),
        ),
        data: (data) {
          final groups = _parseGroups(data['savings_groups']);
          final group = groups.firstWhere(
            (g) => g['id']?.toString() == widget.groupId,
            orElse: () => const <String, dynamic>{},
          );

          if (group.isEmpty) {
            return const CoolEmptyView(
              message: 'Savings group not found',
              icon: CoolIcons.error,
            );
          }

          return _buildGroupDetail(group);
        },
      ),
    );
  }

  Widget _buildGroupDetail(Map<String, dynamic> group) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    final name = group['name']?.toString() ?? 'Unnamed';
    final description = group['description']?.toString();
    final targetAmount = _asInt(group['target_amount']);
    final monthlyContribution = _asInt(group['monthly_contribution']);
    final totalCollected = _asInt(group['total_collected']);
    final frequency = group['frequency']?.toString() ?? 'monthly';
    final inviteCode = group['invite_code']?.toString() ?? '';
    final isClosed = group['is_closed'] == true;
    final members = _parseGroups(group['members']);

    return ListView(
      padding: const EdgeInsets.only(bottom: CoolSpace.x7),
      children: [
        // ── Group header ──────────────────────────────────
        CoolCard(
          backgroundColor: colors.operationalSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (isClosed ? colors.danger : colors.success)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(CoolRadii.pill),
                    ),
                    child: Text(
                      isClosed ? context.l10n.adminSavingsClosedStatus : context.l10n.adminSavingsActiveStatus,
                      style: context.coolText.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w800,
                        color: isClosed ? colors.danger : colors.success,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: CoolSpace.x2),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: CoolSpace.x4),
              Wrap(
                spacing: CoolSpace.x3,
                runSpacing: CoolSpace.x2,
                children: [
                  _InfoChip(
                    label: '${formatWholeMoneyAmount(targetAmount)} target',
                    icon: CoolIcons.flagFilled,
                  ),
                  _InfoChip(
                    label: '${formatWholeMoneyAmount(monthlyContribution)} / mo',
                    icon: CoolIcons.calendar,
                  ),
                  _InfoChip(
                    label: '${formatWholeMoneyAmount(totalCollected)} collected',
                    icon: CoolIcons.wallet,
                  ),
                  _InfoChip(
                    label: frequency.replaceAll('_', ' '),
                    icon: CoolIcons.loop,
                  ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: inviteCode));
                        CoolToast.success(context, 'Copied');
                      },
                      child: _InfoChip(
                        label: inviteCode,
                        icon: CoolIcons.qrCodeRounded,
                      ),
                    ),
                ],
              ),
              if (!isClosed) ...[
                const SizedBox(height: CoolSpace.x4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleCloseGroup(group['id']?.toString()),
                    icon: const Icon(CoolIcons.lock, size: 16),
                    label: const Text('Close Group'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.danger,
                      side: BorderSide(
                        color: colors.danger.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(CoolRadii.sm),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x5),

        // ── Tabs ──────────────────────────────────────────
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final tab in _DetailTab.values) ...[
                ChoiceChip(
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
                        ? colors.accentStrong
                        : colors.secondaryText,
                  ),
                  side: BorderSide.none,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.all(Radius.circular(CoolRadii.pill)),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x4),

        // ── Tab content ───────────────────────────────────
        switch (_activeTab) {
          _DetailTab.members => _buildMembers(
              members, group['id']?.toString() ?? ''),
          _DetailTab.allocations => _buildAllocations(
              members, group['id']?.toString() ?? ''),
        },
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Members tab
  // ────────────────────────────────────────────────────────────────

  Widget _buildMembers(
    List<Map<String, dynamic>> members,
    String groupId,
  ) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: CoolSpace.x3),

        // ── Add member form ──
        CoolCard(
          backgroundColor: colors.operationalSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addMemberPhoneController,
                      keyboardType: TextInputType.phone,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                      decoration: InputDecoration(
                        hintText: '+250788…',
                        hintStyle: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.tertiaryText),
                        prefixIcon: Icon(CoolIcons.phone, size: 18,
                            color: colors.tertiaryText),
                        prefixIconConstraints: const BoxConstraints(
                            minWidth: 36),
                        filled: true,
                        fillColor: colors.chipBackground,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _addMemberNameController,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Name',
                        hintStyle: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.tertiaryText),
                        prefixIcon: Icon(CoolIcons.profile, size: 18,
                            color: colors.tertiaryText),
                        prefixIconConstraints: const BoxConstraints(
                            minWidth: 36),
                        filled: true,
                        fillColor: colors.chipBackground,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(CoolRadii.sm),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x3),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isAddingMember
                      ? null
                      : () => _handleAddMemberByPhone(groupId),
                  icon: const Icon(CoolIcons.personAdd, size: 16),
                  label: Text(_isAddingMember ? context.l10n.adminSavingsAddingMember : context.l10n.adminSavingsAddMember),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.sm),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x4),

        // ── Member list ──
        if (members.isEmpty)
          const CoolEmptyView(
            message: 'No members yet',
            icon: CoolIcons.people,
          )
        else
          for (final member in members) ...[
            CoolCard(
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.info.withValues(alpha: 0.12),
                      borderRadius: _chipRadius,
                    ),
                    child: Icon(
                      CoolIcons.person,
                      size: 18,
                      color: colors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member['display_name']?.toString() ?? 'Member',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                        ),
                        if (member['phone'] != null)
                          Text(
                            member['phone'].toString(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.tertiaryText,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      CoolIcons.removeCircle,
                      color: colors.danger,
                      size: 20,
                    ),
                    tooltip: context.l10n.adminSavingsRemoveMemberTooltip,
                    onPressed: () => _handleRemoveMember(
                      groupId,
                      member['user_id']?.toString() ?? '',
                      member['display_name']?.toString() ?? 'this member',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: CoolSpace.x2),
          ],
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Allocations tab
  // ────────────────────────────────────────────────────────────────

  Widget _buildAllocations(
    List<Map<String, dynamic>> members,
    String groupId,
  ) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: CoolSpace.x3),

        CoolCard(
          backgroundColor: colors.operationalSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Member selector ──
              if (members.isEmpty)
                const CoolEmptyView(
                  message: 'No members',
                  icon: CoolIcons.people,
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.chipBackground,
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    value: _selectedMemberUserId,
                    icon: Icon(CoolIcons.unfoldMore,
                        size: 18, color: colors.tertiaryText),
                    hint: Row(
                      children: [
                        Icon(CoolIcons.person, size: 18,
                            color: colors.tertiaryText),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.adminSavingsSelectMember,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.tertiaryText,
                          ),
                        ),
                      ],
                    ),
                    dropdownColor: colors.cardSurface,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.primaryText,
                    ),
                    items: members.map((m) {
                      final userId = m['user_id']?.toString() ?? '';
                      final name = m['display_name']?.toString() ?? 'Member';
                      return DropdownMenuItem(
                        value: userId,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        setState(() => _selectedMemberUserId = v),
                  ),
                ),

              const SizedBox(height: CoolSpace.x3),
              TextField(
                controller: _allocationAmountController,
                keyboardType: TextInputType.number,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: 'Amount',
                  hintStyle: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.tertiaryText),
                  prefixIcon: Icon(CoolIcons.paymentsFilled, size: 18,
                      color: colors.tertiaryText),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixText: 'RWF',
                  suffixStyle: theme.textTheme.labelSmall?.copyWith(
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  filled: true,
                  fillColor: colors.chipBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              TextField(
                controller: _allocationNoteController,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: 'Note',
                  hintStyle: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.tertiaryText),
                  prefixIcon: Icon(CoolIcons.stickyNote, size: 18,
                      color: colors.tertiaryText),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  filled: true,
                  fillColor: colors.chipBackground,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(CoolRadii.sm),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: CoolSpace.x5),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isAllocating || _selectedMemberUserId == null
                      ? null
                      : () => _handleAllocateContribution(groupId),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(CoolRadii.sm),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    _isAllocating ? context.l10n.adminSavingsAllocating : context.l10n.adminSavingsAllocate,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Actions
  // ────────────────────────────────────────────────────────────────

  Future<void> _handleAddMemberByPhone(String groupId) async {
    final phone = _addMemberPhoneController.text.trim();
    if (phone.isEmpty) {
      CoolToast.error(context, context.l10n.adminSavingsPhoneRequired);
      return;
    }

    setState(() => _isAddingMember = true);
    try {
      final repo = ref.read(adminSavingsRepositoryProvider);
      await repo.bulkAddGroupMembers(
        groupId: groupId,
        members: [
          {
            'phone': phone,
            'display_name': _addMemberNameController.text.trim(),
          },
        ],
      );
      if (!mounted) return;
      _addMemberPhoneController.clear();
      _addMemberNameController.clear();
      CoolToast.success(context, context.l10n.adminSavingsMemberAdded);
      ref.invalidate(adminSavingsGroupsDetailProvider);
    } catch (e) {
      if (!mounted) return;
      CoolToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _isAddingMember = false);
    }
  }

  Future<void> _handleRemoveMember(
    String groupId,
    String userId,
    String name,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.adminSavingsRemoveMemberTitle),
        content: Text(context.l10n.adminSavingsRemoveMemberMessage(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.adminSavingsRemoveMemberTitle),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final repo = ref.read(adminSavingsRepositoryProvider);
      await repo.removeGroupMember(groupId: groupId, userId: userId);
      if (!mounted) return;
      CoolToast.success(context, context.l10n.adminSavingsMemberRemoved(name));
      ref.invalidate(adminSavingsGroupsDetailProvider);
    } catch (e) {
      if (!mounted) return;
      CoolToast.error(context, e.toString());
    }
  }

  Future<void> _handleAllocateContribution(String groupId) async {
    final amount = int.tryParse(_allocationAmountController.text.trim());
    if (amount == null || amount <= 0) {
      CoolToast.error(context, context.l10n.adminSavingsEnterValidAmount);
      return;
    }

    setState(() => _isAllocating = true);
    try {
      final repo = ref.read(adminSavingsRepositoryProvider);
      await repo.allocateSavingsContribution(
        groupId: groupId,
        memberUserId: _selectedMemberUserId!,
        amount: amount,
        note: _allocationNoteController.text.trim().isNotEmpty
            ? _allocationNoteController.text.trim()
            : null,
      );
      if (!mounted) return;
      _allocationAmountController.clear();
      _allocationNoteController.clear();
      CoolToast.success(
        context,
        context.l10n.adminSavingsContributionRecorded(formatWholeMoneyAmount(amount)),
      );
      ref.invalidate(adminSavingsGroupsDetailProvider);
    } catch (e) {
      if (!mounted) return;
      CoolToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _isAllocating = false);
    }
  }

  Future<void> _handleCloseGroup(String? groupId) async {
    if (groupId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.adminSavingsCloseGroupTitle),
        content: Text(
          context.l10n.adminSavingsCloseGroupMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.adminSavingsCloseGroup),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final repo = ref.read(adminSavingsRepositoryProvider);
      await repo.updateSavingsGroup(groupId: groupId, isClosed: true);
      if (!mounted) return;
      CoolToast.success(context, context.l10n.adminSavingsGroupClosed);
      ref.invalidate(adminSavingsGroupsDetailProvider);
    } catch (e) {
      if (!mounted) return;
      CoolToast.error(context, e.toString());
    }
  }

  // ── Helpers ──

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

enum _DetailTab {
  members('Members'),
  allocations('Allocations');

  const _DetailTab(this.label);
  final String label;
}

// ═══════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════════════════════

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

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
