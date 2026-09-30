import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';

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
            normalized.contains('open') ||
            normalized.contains('ambiguous') ||
            normalized.contains('unallocated')
        ? CollectStatusTone.warning
        : normalized.contains('failed') ||
              normalized.contains('blocked') ||
              normalized.contains('expired') ||
              normalized.contains('inactive') ||
              normalized.contains('retired')
        ? CollectStatusTone.danger
        : normalized.contains('active') ||
              normalized.contains('allocated') ||
              normalized.contains('confirmed') ||
              normalized.contains('approved') ||
              normalized.contains('balanced') ||
              normalized.contains('completed') ||
              normalized.contains('matched') ||
              normalized.contains('reconciled') ||
              normalized.contains('posted') ||
              normalized.contains('parsed')
        ? CollectStatusTone.success
        : CollectStatusTone.info;
    final foreground = colors.statusForeground(tone);
    final readableLabel = _readableStatus(label);
    return Semantics(
      label: 'Status: $readableLabel',
      child: ExcludeSemantics(
        child: Tooltip(
          message: readableLabel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.statusBackground(tone),
              shape: BoxShape.circle,
              border: Border.all(color: foreground.withValues(alpha: 0.26)),
            ),
            child: SizedBox.square(
              dimension: 32,
              child: Icon(_statusIcon(normalized), size: 17, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _statusIcon(String normalized) {
  if (normalized.contains('registered')) return Icons.person_outline;
  if (normalized.contains('admin')) {
    return Icons.admin_panel_settings_outlined;
  }
  if (normalized.contains('public')) return Icons.public_outlined;
  if (normalized.contains('private')) return Icons.lock_outline;
  if (normalized.contains('archived')) return Icons.archive_outlined;
  if (normalized.contains('inactive') || normalized.contains('retired')) {
    return Icons.pause_circle_outline;
  }
  if (normalized.contains('failed') ||
      normalized.contains('blocked') ||
      normalized.contains('expired')) {
    return Icons.error_outline;
  }
  if (normalized.contains('review') ||
      normalized.contains('ambiguous') ||
      normalized.contains('unallocated')) {
    return Icons.priority_high_rounded;
  }
  if (normalized.contains('pending') || normalized.contains('open')) {
    return Icons.schedule_outlined;
  }
  if (normalized.contains('active') ||
      normalized.contains('allocated') ||
      normalized.contains('confirmed') ||
      normalized.contains('approved') ||
      normalized.contains('balanced') ||
      normalized.contains('completed') ||
      normalized.contains('matched') ||
      normalized.contains('reconciled') ||
      normalized.contains('posted') ||
      normalized.contains('parsed')) {
    return Icons.check_circle_outline;
  }
  return Icons.info_outline;
}

String _readableStatus(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[_-]+'), ' ');
  if (normalized.isEmpty) return 'Unknown';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}
