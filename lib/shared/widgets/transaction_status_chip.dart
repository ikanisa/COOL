import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/cool_foundations.dart';

/// Pill-shaped status chip for transaction and ledger entries.
///
/// Follows the Tactile Monolith chip rules:
/// - Pill-shaped (`CoolRadii.pill`)
/// - Background: semantic color at 12% opacity
/// - Text: Inter w800 in semantic color
/// - No borders (No-Line rule)
class TransactionStatusChip extends StatelessWidget {
  const TransactionStatusChip({required this.status, super.key});

  /// The raw ledger status string (e.g. 'posted', 'draft', 'manual_review').
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final resolved = _resolve(context, status, colors);

    return Semantics(
      label: context.l10n.statusBadgeSemantics(resolved.label),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: resolved.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(resolved.icon, size: 12, color: resolved.color),
              const SizedBox(width: 4),
              Text(
                resolved.label,
                style: context.coolText
                    .mobiLabel(color: resolved.color)
                    .copyWith(letterSpacing: 0.5, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _ResolvedStatus _resolve(
    BuildContext context,
    String status,
    CoolSemanticColors colors,
  ) {
    return switch (status.toLowerCase().trim()) {
      'instruction' ||
      'instructions' ||
      'payment_instruction' ||
      'ussd_instruction' ||
      'qr_instruction' ||
      'awaiting_instruction' => _ResolvedStatus(
        label: context.l10n.instructionUpper,
        color: colors.info,
        icon: CoolIcons.info,
      ),
      'pending' ||
      'pending_review' ||
      'awaiting_confirmation' ||
      'pending_confirmation' ||
      'dialed' ||
      'processing' => _ResolvedStatus(
        label: context.l10n.reviewUpper,
        color: colors.warning,
        icon: CoolIcons.pending,
      ),
      'manual_review' || 'needs_manual_review' => _ResolvedStatus(
        label: context.l10n.manualUpper,
        color: colors.warning,
        icon: CoolIcons.pendingActions,
      ),
      'manually_confirmed' ||
      'manual_confirmed' ||
      'manual_match' ||
      'manual_allocation_confirmed' => _ResolvedStatus(
        label: context.l10n.manualConfirmedUpper,
        color: colors.success,
        icon: CoolIcons.verified,
      ),
      'paid' || 'completed' || 'settled' => _ResolvedStatus(
        label: context.l10n.paidUpper,
        color: colors.success,
        icon: CoolIcons.payment,
      ),
      'posted' => _ResolvedStatus(
        label: context.l10n.postedUpper,
        color: colors.success,
        icon: CoolIcons.selected,
      ),
      'confirmed' => _ResolvedStatus(
        label: context.l10n.confirmedUpper,
        color: colors.success,
        icon: CoolIcons.verified,
      ),
      'draft' || 'created' => _ResolvedStatus(
        label: context.l10n.draftUpper,
        color: colors.neutral,
        icon: CoolIcons.editNote,
      ),
      'suggested' => _ResolvedStatus(
        label: context.l10n.suggestedUpper,
        color: colors.info,
        icon: CoolIcons.autoFix,
      ),
      'disputed' || 'dispute' || 'chargeback' => _ResolvedStatus(
        label: context.l10n.disputedUpper,
        color: colors.danger,
        icon: CoolIcons.warning,
      ),
      'refunded' || 'refund' || 'reversed' => _ResolvedStatus(
        label: context.l10n.refundedUpper,
        color: colors.info,
        icon: CoolIcons.syncAlt,
      ),
      'cancelled' || 'canceled' => _ResolvedStatus(
        label: context.l10n.cancelledUpper,
        color: colors.danger,
        icon: CoolIcons.cancelled,
      ),
      'rejected' || 'failed' || 'expired' => _ResolvedStatus(
        label: context.l10n.rejectedUpper,
        color: colors.danger,
        icon: CoolIcons.cancelled,
      ),
      _ => _ResolvedStatus(
        label: status.toUpperCase(),
        color: colors.neutral,
        icon: CoolIcons.unselected,
      ),
    };
  }
}

class _ResolvedStatus {
  const _ResolvedStatus({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}
