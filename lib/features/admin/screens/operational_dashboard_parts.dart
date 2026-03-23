part of 'operational_dashboard_screen.dart';

class _ManualReviewCard extends StatelessWidget {
  const _ManualReviewCard({
    required this.row,
    required this.isBusy,
    required this.onClose,
  });

  final Map<String, dynamic> row;
  final bool isBusy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final reviewKind = _manualReviewKind(row);
    final amount = _count(row['amount']);
    final currency = _text(row['currency']) ?? 'RWF';
    final sender = _text(row['sender']) ?? 'Unknown sender';
    final notes = _text(row['notes']) ?? 'Manual review required.';
    final smsPreview = _text(row['sms_preview']);
    final counterparty =
        _text(row['payer_name']) ??
        _text(row['payee_name']) ??
        _text(row['payee_number_or_code']) ??
        _text(row['merchant_code']);

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      borderColor: _reviewKindColor(context, reviewKind).withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sender,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
              _Badge(
                label: _reviewKindLabel(reviewKind).toUpperCase(),
                color: _reviewKindColor(context, reviewKind),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount > 0 ? '$amount $currency' : 'No parsed amount',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            notes,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          _FactLine(label: 'Type', value: _text(row['tx_type']) ?? 'unknown'),
          _FactLine(
            label: 'Category',
            value: _text(row['tx_category']) ?? 'uncategorized',
          ),
          if (counterparty != null)
            _FactLine(label: 'Counterparty', value: counterparty),
          if (_text(row['momo_tx_id']) case final momoTxId?)
            _FactLine(label: 'Tx ID', value: momoTxId),
          _FactLine(
            label: 'Received',
            value: _formatTimestamp(row['sms_received_at']),
          ),
          if (smsPreview != null) ...[
            const SizedBox(height: CoolSpace.x2),
            Text(
              smsPreview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.tertiaryText,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: CoolSpace.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: isBusy ? null : onClose,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.accent,
                side: BorderSide(color: colors.accent.withValues(alpha: 0.7)),
                minimumSize: const Size(0, CoolTapTargets.minimum),
              ),
              icon: isBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt_outlined, size: 16),
              label: Text(isBusy ? 'Closing...' : 'Close review'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SenderInventoryCard extends StatelessWidget {
  const _SenderInventoryCard({
    required this.row,
    required this.isBusy,
    required this.onAcknowledge,
  });

  final Map<String, dynamic> row;
  final bool isBusy;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final approvalStatus = _text(row['approval_status']) ?? 'unknown';
    final senderKind = _text(row['sender_kind']) ?? 'alias';
    final latestParseStatus = _prettyToken(_text(row['latest_parse_status']));
    final latestMatchStatus = _prettyToken(_text(row['latest_match_status']));
    final ingestionSource = _prettyToken(_text(row['last_ingestion_source']));
    final resolutionStatus = _text(row['resolution_status']);
    final resolutionNote = _text(row['resolution_note']);
    final isAcknowledged = resolutionStatus == 'acknowledged_legacy';

    return CoolCard(
      backgroundColor: colors.operationalSurface,
      useGradient: false,
      borderColor: _senderApprovalColor(
        context,
        isAcknowledged ? 'acknowledged' : approvalStatus,
      ).withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(row['sender']) ?? 'Unknown sender',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: CoolSpace.x1),
                    Text(
                      'Normalized as ${_text(row['sender_token']) ?? 'unknown'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.tertiaryText,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Badge(
                    label: isAcknowledged
                        ? 'ACKNOWLEDGED'
                        : approvalStatus.toUpperCase(),
                    color: _senderApprovalColor(
                      context,
                      isAcknowledged ? 'acknowledged' : approvalStatus,
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x2),
                  _Badge(
                    label: senderKind.toUpperCase(),
                    color: colors.neutral,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Raw', value: '${_count(row['raw_count'])}'),
              _MetricChip(
                label: 'Users',
                value: '${_count(row['user_count'])}',
              ),
              _MetricChip(
                label: 'Pending Raw',
                value: '${_count(row['pending_raw_count'])}',
              ),
              _MetricChip(
                label: 'Parsed',
                value: '${_count(row['parsed_count'])}',
              ),
              _MetricChip(
                label: 'Open Review',
                value: '${_count(row['open_review_count'])}',
              ),
              _MetricChip(
                label: 'Rejected',
                value: '${_count(row['rejected_count'])}',
              ),
              if (_count(row['matched_count']) > 0)
                _MetricChip(
                  label: 'Matched',
                  value: '${_count(row['matched_count'])}',
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),
          _FactLine(label: 'Latest parse', value: latestParseStatus),
          _FactLine(label: 'Latest reconcile', value: latestMatchStatus),
          _FactLine(label: 'Source', value: ingestionSource),
          if (resolutionStatus != null)
            _FactLine(
              label: 'Resolution',
              value: _prettyToken(resolutionStatus),
            ),
          _FactLine(
            label: 'First seen',
            value: _formatTimestamp(row['first_seen_at']),
          ),
          _FactLine(
            label: 'Last seen',
            value: _formatTimestamp(row['last_seen_at']),
          ),
          if (_text(row['resolved_at']) case final resolvedAt?)
            _FactLine(label: 'Resolved', value: _formatTimestamp(resolvedAt)),
          if (resolutionNote != null) ...[
            const SizedBox(height: CoolSpace.x2),
            Text(
              resolutionNote,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.secondaryText,
                height: 1.45,
              ),
            ),
          ],
          if (!isAcknowledged) ...[
            const SizedBox(height: CoolSpace.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onAcknowledge,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.accent,
                  side: BorderSide(color: colors.accent.withValues(alpha: 0.7)),
                  minimumSize: const Size(0, CoolTapTargets.minimum),
                ),
                icon: isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fact_check_outlined, size: 16),
                label: Text(isBusy ? 'Saving...' : 'Acknowledge legacy'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
                  Expanded(
                    child: _MetricChip(label: 'OK', value: '$okCount'),
                  ),
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
                value: (_text(row['service']) ?? 'unknown').replaceAll(
                  '_',
                  ' ',
                ),
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
  final isAcknowledged =
      _text(row['resolution_status']) == 'acknowledged_legacy';
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
