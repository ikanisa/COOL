import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';

/// Pill-shaped status chip for transaction and ledger entries.
///
/// Follows the Tactile Monolith chip rules:
/// - Pill-shaped (`CoolRadii.pill`)
/// - Background: semantic color at 12% opacity
/// - Text: Inter w700 in semantic color
/// - No borders (No-Line rule)
class TransactionStatusChip extends StatelessWidget {
  const TransactionStatusChip({required this.status, super.key});

  /// The raw ledger status string (e.g. 'posted', 'draft', 'manual_review').
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final resolved = _resolve(status, colors);

    return Container(
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
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: resolved.color,
              letterSpacing: 0.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  static _ResolvedStatus _resolve(String status, CoolSemanticColors colors) {
    return switch (status.toLowerCase().trim()) {
      'posted' || 'completed' => _ResolvedStatus(
        label: 'POSTED',
        color: colors.success,
        icon: Icons.check_circle_rounded,
      ),
      'confirmed' => _ResolvedStatus(
        label: 'CONFIRMED',
        color: colors.success,
        icon: Icons.verified_rounded,
      ),
      'draft' => _ResolvedStatus(
        label: 'DRAFT',
        color: colors.neutral,
        icon: Icons.edit_note_rounded,
      ),
      'pending' || 'pending_review' => _ResolvedStatus(
        label: 'REVIEW',
        color: colors.warning,
        icon: Icons.pending_rounded,
      ),
      'manual_review' => _ResolvedStatus(
        label: 'MANUAL',
        color: colors.warning,
        icon: Icons.pending_actions_rounded,
      ),
      'suggested' => _ResolvedStatus(
        label: 'SUGGESTED',
        color: colors.info,
        icon: Icons.auto_fix_high_rounded,
      ),
      'rejected' || 'cancelled' => _ResolvedStatus(
        label: 'REJECTED',
        color: colors.danger,
        icon: Icons.cancel_rounded,
      ),
      _ => _ResolvedStatus(
        label: status.toUpperCase(),
        color: colors.neutral,
        icon: Icons.circle_outlined,
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
