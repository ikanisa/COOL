part of 'operational_dashboard_screen.dart';

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      padding: _operationalMetricChipPadding(),
      decoration: BoxDecoration(
        color: colors.inputSurface,
        borderRadius: _operationalPillRadius,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colors.primaryText,
        ),
      ),
    );
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.4,
            ),
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x1),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: _operationalBadgePadding(),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: _operationalPillRadius,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  final colors = context.coolSemanticColors;
  switch (status) {
    case 'healthy':
    case 'ok':
      return colors.success;
    case 'degraded':
    case 'warn':
    case 'warning':
      return colors.warning;
    case 'failing':
    case 'error':
      return colors.danger;
    default:
      return colors.neutral;
  }
}

Color _severityColor(BuildContext context, String severity) {
  final colors = context.coolSemanticColors;
  switch (severity) {
    case 'critical':
      return colors.danger;
    case 'warning':
      return colors.warning;
    default:
      return colors.neutral;
  }
}

Color _senderApprovalColor(BuildContext context, String approvalStatus) {
  final colors = context.coolSemanticColors;
  switch (approvalStatus) {
    case 'acknowledged':
      return colors.accent;
    case 'approved':
      return colors.success;
    case 'unsupported':
      return colors.danger;
    default:
      return colors.neutral;
  }
}

String? _text(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null' || text == '-infinity') {
    return null;
  }
  return text;
}

int _count(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatTimestamp(dynamic value) {
  final text = _text(value);
  if (text == null) {
    return 'No signal yet';
  }

  final timestamp = DateTime.tryParse(text)?.toLocal();
  if (timestamp == null) {
    return text;
  }

  return DateFormat('MMM d, HH:mm').format(timestamp);
}

String _prettyToken(String? value) {
  final text = _text(value);
  if (text == null) {
    return 'unknown';
  }
  return text.replaceAll('_', ' ');
}

String _metricSource(String? metricKey) {
  switch (metricKey) {
    case 'device_sync':
    case 'sender_drift':
    case 'retry_queue':
      return 'Device-reported Android sync audits';
    case 'parsing':
    case 'reconciliation':
    case 'sender_inventory':
    case 'migration_safety':
    case 'retention':
      return 'Server-observed SMS pipeline data';
    default:
      return 'Mixed operational telemetry';
  }
}

List<Map<String, dynamic>> _visibleSenderInventoryRows(
  List<Map<String, dynamic>> rows,
  String filter,
) {
  if (filter == 'all') {
    return rows;
  }
  return rows
      .where((row) => _senderInventoryMatchesFilter(row, filter))
      .toList(growable: false);
}

bool _senderInventoryMatchesFilter(Map<String, dynamic> row, String filter) {
  final isAcknowledged = _text(row['resolution_status']) == 'acknowledged_legacy';
  switch (filter) {
    case 'acknowledged':
      return isAcknowledged;
    case 'unresolved':
      return !isAcknowledged;
    default:
      return true;
  }
}

String _senderInventoryEmptyMessage(
  List<Map<String, dynamic>> rows,
  String filter,
) {
  final acknowledgedCount = rows
      .where((row) => _senderInventoryMatchesFilter(row, 'acknowledged'))
      .length;
  switch (filter) {
    case 'acknowledged':
      return 'No acknowledged sender history matches the current filter.';
    case 'unresolved':
      if (acknowledgedCount > 0) {
        return 'No unresolved unsupported sender backlogs remain. Switch to Acknowledged ($acknowledgedCount) to review preserved history.';
      }
      return 'No unresolved unsupported sender backlogs remain.';
    default:
      return 'No sender audit rows matched the current filter.';
  }
}

List<Widget> _spacedChildren<T>(
  Iterable<T> items,
  Widget Function(T item) builder, {
  double spacing = CoolSpace.x3,
}) {
  final values = items.toList(growable: false);
  final children = <Widget>[];
  for (var index = 0; index < values.length; index++) {
    if (index > 0) {
      children.add(SizedBox(height: spacing));
    }
    children.add(builder(values[index]));
  }
  return children;
}

List<Map<String, dynamic>> _visibleManualReviews(
  List<Map<String, dynamic>> rows,
  String filter,
) {
  if (filter == 'all') {
    return rows;
  }
  return rows
      .where((row) => _manualReviewKind(row) == filter)
      .toList(growable: false);
}

String _manualReviewKind(Map<String, dynamic> row) {
  return _text(row['review_kind']) ?? 'needs_review';
}

String _reviewKindLabel(String kind) {
  switch (kind) {
    case 'non_actionable':
      return 'Non-actionable';
    case 'unmatched_payment':
      return 'Unmatched';
    default:
      return 'Needs review';
  }
}

Color _reviewKindColor(BuildContext context, String kind) {
  final colors = context.coolSemanticColors;
  switch (kind) {
    case 'non_actionable':
      return colors.neutral;
    case 'unmatched_payment':
      return colors.warning;
    default:
      return colors.danger;
  }
}
