part of 'admin_runtime.dart';

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.count,
  });

  final String title;
  final int? count;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 500;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (compact
                                        ? Theme.of(
                                            context,
                                          ).textTheme.titleMedium
                                        : Theme.of(
                                            context,
                                          ).textTheme.titleLarge)
                                    ?.copyWith(
                                      color: colors.textPrimary,
                                      fontWeight: CollectTypography.weightBold,
                                    ),
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surfaceRaised,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.borderSoft),
                            ),
                            child: SizedBox.square(
                              dimension: 26,
                              child: Center(
                                child: Text(
                                  '$count',
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: colors.textSecondary,
                                        fontWeight:
                                            CollectTypography.weightBold,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: actionLabel,
                onPressed: onAction,
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Icon(
            _adminOverviewHeaderIcon(label),
            size: 17,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

IconData _adminOverviewHeaderIcon(String label) => switch (label) {
  'Record' => Icons.receipt_long_outlined,
  'MoMo number' => Icons.phone_android_outlined,
  'Amount' => Icons.payments_outlined,
  'Status' => Icons.fact_check_outlined,
  'Age' => Icons.schedule_outlined,
  'Action' => Icons.tune_outlined,
  'Proposed group' => Icons.groups_outlined,
  'Requested' => Icons.calendar_today_outlined,
  'Maker / checker' => Icons.verified_user_outlined,
  _ => Icons.info_outline,
};

class _TableValue extends StatelessWidget {
  const _TableValue(this.value, {this.strong = false});

  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: strong ? colors.textPrimary : colors.textSecondary,
          fontWeight: strong
              ? CollectTypography.weightBold
              : CollectTypography.weightRegular,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RecordSummary extends StatelessWidget {
  const _RecordSummary({required this.row, this.referenceFirst = false});

  final AdminTableRowData row;
  final bool referenceFirst;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            referenceFirst ? _reference(row) : row.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: CollectTypography.weightBold,
            ),
          ),
          if (!referenceFirst) ...[
            const SizedBox(height: 2),
            Text(
              _reference(row),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

BoxDecoration _overviewPanelDecoration(CollectColors colors) {
  return BoxDecoration(
    color: colors.surfaceReadable,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: colors.borderSoft),
  );
}

CollectStatusTone _metricTone(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('active') || normalized.contains('allocated')) {
    return CollectStatusTone.success;
  }
  if (normalized.contains('review') || normalized.contains('pending')) {
    return CollectStatusTone.warning;
  }
  return CollectStatusTone.info;
}

IconData _metricIcon(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('exception')) return Icons.report_problem_outlined;
  if (normalized.contains('approval')) return Icons.fact_check_outlined;
  if (normalized.contains('unreconciled')) {
    return Icons.pending_actions_outlined;
  }
  if (normalized.contains('evidence')) return Icons.verified_outlined;
  return Icons.account_balance_outlined;
}

String _metricValue(
  List<AdminMetric> metrics,
  String label, {
  required String fallback,
}) {
  for (final metric in metrics) {
    if (metric.label.toLowerCase() == label.toLowerCase()) return metric.value;
  }
  return fallback;
}

int? _metricInt(List<AdminMetric> metrics, String label) {
  final value = _metricValue(metrics, label, fallback: '');
  try {
    return exactJsonInteger(
      value,
      field: label,
      minimum: 0,
      allowDigitString: true,
    );
  } on FormatException {
    return null;
  }
}

String _extraString(AdminTableRowData row, String key, String fallback) {
  final value = row.extra[key];
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}

String _sender(AdminTableRowData row) {
  if (_rail(row) != 'rw_momo') return '—';
  return _momoSender(row);
}

String _reference(AdminTableRowData row) {
  return adminCompactTransactionReference(
    _extraString(row, 'reference', 'Ref ${row.id}'),
  );
}

String _allocatedTo(AdminTableRowData row) {
  return _extraString(row, 'allocated_to', 'Verified group');
}

String _operator(AdminTableRowData row) {
  return _extraString(row, 'operator', 'Operations');
}

String _age(AdminTableRowData row) {
  final explicit = _extraString(row, 'age', '');
  if (explicit.isNotEmpty) return _compactAge(explicit);
  final createdAt = row.createdAt;
  if (createdAt == null) return '—';
  final duration = DateTime.now().toUtc().difference(createdAt);
  if (duration.isNegative) return 'just now';
  if (duration.inMinutes < 60) return '${math.max(1, duration.inMinutes)}m';
  if (duration.inHours < 24) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
  return '${duration.inDays}d';
}

String _compactAge(String value) {
  final normalized = value.trim();
  final postgresInterval = RegExp(
    r'^(?:(\d+)\s+days?\s+)?(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$',
  ).firstMatch(normalized);
  if (postgresInterval == null) return normalized;

  final days = int.tryParse(postgresInterval.group(1) ?? '') ?? 0;
  final hours = int.tryParse(postgresInterval.group(2) ?? '') ?? 0;
  final minutes = int.tryParse(postgresInterval.group(3) ?? '') ?? 0;
  if (days > 0) return '${days}d';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${math.max(1, minutes)}m';
}

String _oldestAge(List<AdminTableRowData> rows) {
  if (rows.isEmpty) return '—';
  var oldest = rows.first;
  var oldestMinutes = _ageMinutes(_age(oldest));
  for (final row in rows.skip(1)) {
    final minutes = _ageMinutes(_age(row));
    if (minutes > oldestMinutes) {
      oldest = row;
      oldestMinutes = minutes;
    }
  }
  return _age(oldest);
}

int _ageMinutes(String value) {
  final hours = RegExp(r'(\d+)h').firstMatch(value);
  final minutes = RegExp(r'(\d+)m').firstMatch(value);
  final days = RegExp(r'(\d+)d').firstMatch(value);
  return (int.tryParse(days?.group(1) ?? '') ?? 0) * 1440 +
      (int.tryParse(hours?.group(1) ?? '') ?? 0) * 60 +
      (int.tryParse(minutes?.group(1) ?? '') ?? 0);
}

String _amount(AdminTableRowData row) {
  return _transactionDisplayAmount(row);
}

String _dateTime(DateTime? value) {
  if (value == null) return '—';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)} ${_month(value.month)} ${value.year}, ${two(value.hour)}:${two(value.minute)}';
}

String _month(int value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[value.clamp(1, 12) - 1];
}

String _compactSla(String? target) {
  if (target == null || target.trim().isEmpty) return 'Not available';
  if (RegExp(r'next\s+business\s+day', caseSensitive: false).hasMatch(target)) {
    return 'Next business day';
  }
  final match = RegExp(
    r'(\d+)\s*(?:business\s*)?hours?',
    caseSensitive: false,
  ).firstMatch(target);
  if (match != null) return '< ${match.group(1)}h';
  return target;
}
