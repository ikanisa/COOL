import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_typography.dart';

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final normalized = label.toLowerCase();
    final tone =
        normalized.contains('review') ||
            normalized.contains('pending') ||
            normalized.contains('open')
        ? CollectStatusTone.warning
        : normalized.contains('failed') ||
              normalized.contains('blocked') ||
              normalized.contains('expired')
        ? CollectStatusTone.danger
        : normalized.contains('active') ||
              normalized.contains('allocated') ||
              normalized.contains('confirmed')
        ? CollectStatusTone.success
        : CollectStatusTone.info;
    final foreground = colors.statusForeground(tone);
    return Semantics(
      label: 'Status $label',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.statusBackground(tone),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: foreground.withValues(alpha: 0.26)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: CollectTypography.weightBold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
