part of 'operational_dashboard_screen.dart';

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final status = _text(row['health_status']) ?? 'unknown';
    final issueCount = _count(row['issue_count']);
    final okCount = _count(row['ok_count_24h']);
    final warnCount = _count(row['warn_count_24h']);
    final errorCount = _count(row['error_count_24h']);

    return CoolCard(
      backgroundColor: colors.analyticsSurface,
      useGradient: false,
      borderColor: _statusColor(context, status).withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(row['label']) ?? 'Surface',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              _Badge(
                label: status.toUpperCase(),
                color: _statusColor(context, status),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Column(
            children: [
              Row(
                children: [
                  Expanded(child: _MetricChip(label: 'OK', value: '$okCount')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricChip(label: 'Warn', value: '$warnCount'),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x2),
              Row(
                children: [
                  Expanded(
                    child: _MetricChip(label: 'Error', value: '$errorCount'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricChip(label: 'Issues', value: '$issueCount'),
                  ),
                ],
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

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final severity = _text(row['severity']) ?? 'warning';
    final reference = _text(row['reference']);
    final subjectTable = _text(row['subject_table']);
    final subjectId = _text(row['subject_id']);

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      borderColor: _severityColor(context, severity).withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text(row['title']) ?? 'Issue',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              _Badge(
                label: severity.toUpperCase(),
                color: _severityColor(context, severity),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            _text(row['detail']) ?? 'No detail available.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.45,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FactLine(
                label: 'Service',
                value: (_text(row['service']) ?? 'unknown').replaceAll('_', ' '),
              ),
              if (reference != null)
                _FactLine(label: 'Reference', value: reference),
              if (subjectTable != null)
                _FactLine(label: 'Table', value: subjectTable),
              if (subjectId != null)
                _FactLine(label: 'Record', value: subjectId),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Seen ${_formatTimestamp(row['first_seen_at'])} • Last signal ${_formatTimestamp(row['last_seen_at'])}',
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

class _EventTile extends StatelessWidget {
  const _EventTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final status = _text(row['status']) ?? 'ok';
    final functionName = _text(row['function_name']);

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      borderColor: _statusColor(context, status).withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(
                label: status.toUpperCase(),
                color: _statusColor(context, status),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _text(row['service']) ?? 'service',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              Text(
                _formatTimestamp(row['occurred_at']),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.tertiaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            _text(row['message']) ?? 'No message',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FactLine(
                label: 'Component',
                value: _text(row['component']) ?? 'general',
              ),
              if (functionName != null)
                _FactLine(label: 'Function', value: functionName),
              if (_text(row['issue_code']) case final issueCode?)
                _FactLine(label: 'Code', value: issueCode),
            ],
          ),
        ],
      ),
    );
  }
}
