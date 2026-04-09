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
