part of 'operational_dashboard_screen.dart';

// Legacy _DashboardCard, _IssueCard, _EventTile removed —
// dashboard/issues/events now rendered via AdminDataTableCard.

class _OperationalMetricCard extends StatelessWidget {
  const _OperationalMetricCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final healthStatus = _text(row['health_status']) ?? 'unknown';
    final metricKey = _text(row['metric_key']);
    final primaryLabel = _text(row['primary_label']);
    final secondaryLabel = _text(row['secondary_label']);
    final tertiaryLabel = _text(row['tertiary_label']);

    return CoolCard(
      backgroundColor: colors.analyticsSurface,
      useGradient: false,
      borderColor: _statusColor(context, healthStatus).withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(row['label']) ?? 'Metric',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              _Badge(
                label: healthStatus.toUpperCase(),
                color: _statusColor(context, healthStatus),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (primaryLabel != null)
                _MetricChip(
                  label: primaryLabel,
                  value: '${_count(row['primary_value'])}',
                ),
              if (secondaryLabel != null)
                _MetricChip(
                  label: secondaryLabel,
                  value: '${_count(row['secondary_value'])}',
                ),
              if (tertiaryLabel != null)
                _MetricChip(
                  label: tertiaryLabel,
                  value: '${_count(row['tertiary_value'])}',
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            _text(row['summary']) ?? 'No summary available.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _FactLine(label: 'Source', value: _metricSource(metricKey)),
          const SizedBox(height: CoolSpace.x1),
          Text(
            'Last signal: ${_formatTimestamp(row['last_signal_at'])}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.tertiaryText,
            ),
          ),
        ],
      ),
    );
  }
}
