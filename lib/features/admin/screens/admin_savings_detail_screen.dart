import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../shared/widgets/admin_detail_scaffold.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_toast.dart';

import '../providers/admin_providers.dart';
import 'admin_savings_detail_widgets.dart';

part 'admin_savings_detail_screen_parts.dart';

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
  static const _autoRefreshInterval = Duration(seconds: 15);

  SavingsDetailTab _activeTab = SavingsDetailTab.members;
  Timer? _autoRefreshTimer;

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
            context.l10n.adminSavingsErrorPrefix(error.toString()),
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.danger),
          ),
        ),
        data: (data) {
          final groups = _parseGroups(data['savings_groups']);
          final group = groups.firstWhere(
            (g) => g['id']?.toString() == widget.groupId,
            orElse: () => const <String, dynamic>{},
          );

          if (group.isEmpty) {
            return CoolEmptyView(
              message: context.l10n.adminSavingsGroupNotFound,
              icon: CoolIcons.error,
            );
          }

          return _buildGroupDetail(group);
        },
      ),
    );
  }

  void _selectTab(SavingsDetailTab tab) => setState(() => _activeTab = tab);

  void _selectMemberUserId(String? userId) {
    setState(() => _selectedMemberUserId = userId);
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
            child: Text(context.l10n.adminSavingsCancelAction),
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
        context.l10n.adminSavingsContributionRecorded(
          formatWholeMoneyAmount(amount),
        ),
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
        content: Text(context.l10n.adminSavingsCloseGroupMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.adminSavingsCancelAction),
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
