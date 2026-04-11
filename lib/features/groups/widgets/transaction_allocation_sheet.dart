import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/transaction_status_chip.dart';
import '../../momo/models/momo_statement.dart';

/// A simple group member record for allocation selection.
class _GroupMemberOption {
  const _GroupMemberOption({
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;
}

/// Bottom sheet that allows group admins to view, allocate, unallocate,
/// or reallocate a transaction to/from a group member.
///
/// Follows Tactile Monolith: glassmorphic sheet, pill chips, ambient shadows.
class TransactionAllocationSheet extends ConsumerStatefulWidget {
  const TransactionAllocationSheet({
    required this.entry,
    required this.groupId,
    super.key,
  });

  final PayeePaymentLedgerEntry entry;
  final String groupId;

  /// Show the allocation sheet as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required PayeePaymentLedgerEntry entry,
    required String groupId,
  }) {
    return showCoolBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TransactionAllocationSheet(
        entry: entry,
        groupId: groupId,
      ),
    );
  }

  @override
  ConsumerState<TransactionAllocationSheet> createState() =>
      _TransactionAllocationSheetState();
}

class _TransactionAllocationSheetState
    extends ConsumerState<TransactionAllocationSheet> {
  List<_GroupMemberOption>? _members;
  bool _isLoadingMembers = false;
  String? _selectedMemberId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoadingMembers = true);
    try {
      final client = ref.read(supabaseClientProvider);
      final rows = await client
          .from('group_members')
          .select('user_id, display_name')
          .eq('group_id', widget.groupId)
          .order('display_name', ascending: true);

      if (!mounted) return;

      final members = (rows as List)
          .whereType<Map<dynamic, dynamic>>()
          .map((row) => _GroupMemberOption(
                userId: row['user_id']?.toString() ?? '',
                displayName: row['display_name']?.toString() ?? 'Member',
              ))
          .where((m) => m.userId.isNotEmpty)
          .toList(growable: false);

      setState(() {
        _members = members;
        _isLoadingMembers = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  Future<void> _allocate() async {
    if (_selectedMemberId == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('allocate_transaction_to_member', params: {
        'p_ledger_id': widget.entry.ledgerId,
        'p_group_id': widget.groupId,
        'p_member_user_id': _selectedMemberId,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      CoolToast.success(context, 'Transaction allocated');
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Allocation failed');
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _unallocate() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('unallocate_transaction', params: {
        'p_ledger_id': widget.entry.ledgerId,
        'p_group_id': widget.groupId,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      CoolToast.success(context, 'Transaction unallocated');
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Unallocation failed');
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final entry = widget.entry;
    final isCurrentlyAllocated = entry.payerUserId.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Drag handle ──────────────────────────────────────
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: CoolSpace.x4),
            decoration: BoxDecoration(
              color: colors.borderStrong,
              borderRadius: BorderRadius.circular(CoolRadii.pill),
            ),
          ),
        ),

        // ── Title ────────────────────────────────────────────
        Text(
          'TRANSACTION ALLOCATION',
          style: text.displayCondensed(
            theme.textTheme.titleLarge,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Text(
          'Manage group member assignment',
          style: text.mono(
            theme.textTheme.labelSmall,
            fontWeight: FontWeight.w400,
            color: colors.secondaryText,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: CoolSpace.x5),

        // ── Current entry info ───────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CoolSpace.x4),
          decoration: BoxDecoration(
            color: colors.cardSurface,
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            boxShadow: CoolShadows.ambientFloat(strength: 0.3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      entry.label,
                      style: text.mono(
                        theme.textTheme.titleSmall,
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${entry.amount} ${entry.currency}',
                    style: text.mono(
                      theme.textTheme.titleSmall,
                      fontWeight: FontWeight.w700,
                      color: colors.accentGold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2),
              if (isCurrentlyAllocated)
                Row(
                  children: [
                    Icon(Icons.person_rounded, size: 14, color: colors.success),
                    const SizedBox(width: 6),
                    Text(
                      entry.payerName,
                      style: text.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: colors.success,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    const TransactionStatusChip(status: 'confirmed'),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      size: 14,
                      color: colors.warning,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Not yet allocated',
                      style: text.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w600,
                        color: colors.warning,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    const TransactionStatusChip(status: 'pending_review'),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x5),

        // ── Actions ──────────────────────────────────────────
        if (isCurrentlyAllocated) ...[
          CoolButton(
            label: 'UNALLOCATE',
            variant: CoolButtonVariant.secondary,
            isLoading: _isSubmitting,
            onTap: _isSubmitting ? null : _unallocate,
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'OR REALLOCATE TO ANOTHER MEMBER',
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: colors.tertiaryText,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
        ],

        // ── Member picker ────────────────────────────────────
        if (_isLoadingMembers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: CoolSpace.x4),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_members == null || _members!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CoolSpace.x4),
            child: Text(
              'No group members found.',
              style: text.mono(
                theme.textTheme.bodySmall,
                fontWeight: FontWeight.w400,
                color: colors.secondaryText,
              ),
            ),
          )
        else ...[
          Text(
            isCurrentlyAllocated ? 'Select member:' : 'ALLOCATE TO MEMBER',
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _members!.length,
              itemBuilder: (context, index) {
                final member = _members![index];
                final isSelected = _selectedMemberId == member.userId;
                final isCurrentPayer = member.userId == entry.payerUserId;

                return Material(
                  color: isSelected
                      ? colors.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(CoolRadii.md),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedMemberId = member.userId);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CoolSpace.x3,
                        vertical: CoolSpace.x3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? colors.accent
                                  : Colors.transparent,
                              border: Border.all(
                                color: isSelected
                                    ? colors.accent
                                    : colors.borderStrong,
                                width: 2,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          const SizedBox(width: CoolSpace.x3),
                          Expanded(
                            child: Text(
                              member.displayName,
                              style: text.mono(
                                theme.textTheme.bodyMedium,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? colors.accent
                                    : colors.primaryText,
                              ),
                            ),
                          ),
                          if (isCurrentPayer)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.success.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(CoolRadii.pill),
                              ),
                              child: Text(
                                'CURRENT',
                                style: context.coolText.mobiLabel(
                                  color: colors.success,
                                ).copyWith(letterSpacing: 0.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(
            label: isCurrentlyAllocated
                ? 'CONFIRM REALLOCATION'
                : 'CONFIRM ALLOCATION',
            onTap: _selectedMemberId == null || _isSubmitting
                ? null
                : _allocate,
            isLoading: _isSubmitting,
          ),
        ],
      ],
    );
  }
}
