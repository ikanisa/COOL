import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_state_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/transaction_status_chip.dart';
import '../models/group_member_allocation_option.dart';
import '../providers/groups_provider.dart';
import '../../momo/models/momo_statement.dart';

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
      builder: (context) =>
          TransactionAllocationSheet(entry: entry, groupId: groupId),
    );
  }

  @override
  ConsumerState<TransactionAllocationSheet> createState() =>
      _TransactionAllocationSheetState();
}

class _TransactionAllocationSheetState
    extends ConsumerState<TransactionAllocationSheet> {
  List<GroupMemberAllocationOption>? _members;
  bool _isLoadingMembers = false;
  String? _memberLoadError;
  String? _selectedMemberId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoadingMembers = true;
      _memberLoadError = null;
    });
    try {
      final repository = ref.read(groupActionsProvider);
      final members = await repository.getGroupMemberAllocationOptions(
        widget.groupId,
      );

      if (!mounted) return;

      setState(() {
        _members = members;
        _isLoadingMembers = false;
        _memberLoadError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _members = null;
          _isLoadingMembers = false;
          _memberLoadError = describeUserFacingError(error);
        });
      }
    }
  }

  Future<void> _allocate() async {
    if (_selectedMemberId == null || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final l10n = context.l10n;
      final repository = ref.read(groupActionsProvider);
      await repository.allocateTransactionToMember(
        ledgerId: widget.entry.ledgerId,
        groupId: widget.groupId,
        memberUserId: _selectedMemberId!,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      CoolToast.success(context, l10n.transactionAllocated);
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, context.l10n.allocationFailed);
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _unallocate() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final l10n = context.l10n;
      final repository = ref.read(groupActionsProvider);
      await repository.unallocateTransaction(
        ledgerId: widget.entry.ledgerId,
        groupId: widget.groupId,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      CoolToast.success(context, l10n.transactionUnallocated);
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, context.l10n.unallocationFailed);
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
          l10n.transactionAllocationUpper,
          style: text.displayCondensed(
            theme.textTheme.titleLarge,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
        Text(
          l10n.manageGroupMemberAssignment,
          style: text.mono(
            theme.textTheme.labelSmall,
            fontWeight: FontWeight.w500,
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
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${formatWholeMoneyAmount(entry.amount)} ${entry.currency}',
                    style: text.mono(
                      theme.textTheme.titleSmall,
                      fontWeight: FontWeight.w800,
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
                    Icon(CoolIcons.person, size: 14, color: colors.success),
                    const SizedBox(width: 6),
                    Text(
                      entry.payerName,
                      style: text.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
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
                    Icon(CoolIcons.help, size: 14, color: colors.warning),
                    const SizedBox(width: 6),
                    Text(
                      l10n.notYetAllocated,
                      style: text.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
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
            label: l10n.unallocateUpper,
            variant: CoolButtonVariant.secondary,
            isLoading: _isSubmitting,
            onTap: _isSubmitting ? null : _unallocate,
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            l10n.orReallocateToAnotherMember,
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w700,
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
        else if (_memberLoadError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CoolSpace.x2),
            child: CoolStateView(
              tone: CoolStateTone.error,
              title: l10n.groupMembersLoadFailedTitle,
              message: _memberLoadError!,
              icon: CoolIcons.error,
              actionLabel: l10n.retry,
              onAction: _isSubmitting ? null : () => _loadMembers(),
              compact: true,
              center: false,
            ),
          )
        else if (_members == null || _members!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CoolSpace.x4),
            child: Text(
              l10n.noGroupMembersFound,
              style: text.mono(
                theme.textTheme.bodySmall,
                fontWeight: FontWeight.w500,
                color: colors.secondaryText,
              ),
            ),
          )
        else ...[
          Text(
            isCurrentlyAllocated
                ? l10n.selectMember
                : l10n.allocateToMemberUpper,
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w700,
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
                                    CoolIcons.check,
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
                                fontWeight: FontWeight.w700,
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
                                borderRadius: BorderRadius.circular(
                                  CoolRadii.pill,
                                ),
                              ),
                              child: Text(
                                l10n.currentUpper,
                                style: context.coolText
                                    .mobiLabel(color: colors.success)
                                    .copyWith(letterSpacing: 0.5),
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
                ? l10n.confirmReallocationUpper
                : l10n.confirmAllocationUpper,
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
