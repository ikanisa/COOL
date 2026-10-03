import 'package:flutter/material.dart';

import '../../../app/theme/collect_colors.dart';
import '../../../app/theme/collect_typography.dart';

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({required this.label, this.tone, this.icon, super.key});

  final String label;
  final CollectStatusTone? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final normalized = label.trim().toLowerCase().replaceAll(
      RegExp(r'[_-]+'),
      ' ',
    );
    final effectiveTone =
        tone ??
        (normalized.contains('review') ||
                normalized.contains('pending') ||
                normalized.contains('open') ||
                normalized.contains('ambiguous') ||
                normalized.contains('unallocated') ||
                normalized.contains('unmatched') ||
                normalized.contains('unbalanced') ||
                normalized.contains('unknown') ||
                normalized.contains('uncertain') ||
                normalized.contains('awaiting')
            ? CollectStatusTone.warning
            : normalized.contains('failed') ||
                  normalized.contains('failure') ||
                  normalized.contains('blocked') ||
                  normalized.contains('expired') ||
                  normalized.contains('inactive') ||
                  normalized.contains('retired') ||
                  normalized.contains('undelivered') ||
                  normalized.contains('revoked')
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
                  normalized == 'parsed' ||
                  normalized == 'sent' ||
                  normalized == 'delivered' ||
                  normalized == 'read' ||
                  normalized == 'observed sent'
            ? CollectStatusTone.success
            : CollectStatusTone.info);
    final foreground = colors.statusForeground(effectiveTone);
    final readableLabel = _readableStatus(label);
    return Semantics(
      label: 'Status: $readableLabel',
      child: ExcludeSemantics(
        child: Tooltip(
          message: readableLabel,
          excludeFromSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.statusBackground(effectiveTone),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: foreground.withValues(alpha: 0.26)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 176, minHeight: 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon ?? _statusIcon(normalized),
                      size: 17,
                      color: foreground,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        readableLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: foreground,
                              fontWeight: CollectTypography.weightMedium,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
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
      normalized.contains('failure') ||
      normalized.contains('blocked') ||
      normalized.contains('expired') ||
      normalized.contains('undelivered') ||
      normalized.contains('revoked')) {
    return Icons.error_outline;
  }
  if (normalized.contains('review') ||
      normalized.contains('ambiguous') ||
      normalized.contains('unallocated') ||
      normalized.contains('unmatched') ||
      normalized.contains('unbalanced') ||
      normalized.contains('unknown') ||
      normalized.contains('uncertain')) {
    return Icons.priority_high_rounded;
  }
  if (normalized.contains('pending') ||
      normalized.contains('open') ||
      normalized.contains('awaiting') ||
      normalized == 'queued' ||
      normalized == 'claimed' ||
      normalized == 'sending' ||
      normalized == 'send started' ||
      normalized == 'processing') {
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
      normalized == 'parsed' ||
      normalized == 'sent' ||
      normalized == 'delivered' ||
      normalized == 'read' ||
      normalized == 'observed sent') {
    return Icons.check_circle_outline;
  }
  return Icons.info_outline;
}

String _readableStatus(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[_-]+'), ' ');
  if (normalized.isEmpty) return 'Unknown';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}
