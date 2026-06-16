import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final normalized = label.toLowerCase();
    final accent =
        normalized.contains('review') ||
            normalized.contains('pending') ||
            normalized.contains('open')
        ? colors.warningForeground
        : normalized.contains('failed') ||
              normalized.contains('blocked') ||
              normalized.contains('expired')
        ? colors.dangerForeground
        : normalized.contains('active') ||
              normalized.contains('allocated') ||
              normalized.contains('confirmed')
        ? colors.successForeground
        : colors.infoForeground;
    return Semantics(
      label: 'Status $label',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.26)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
